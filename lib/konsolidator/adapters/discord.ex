defmodule Konsolidator.Adapters.Discord do
  @moduledoc """
  Discord adapter using the Gateway WebSocket API v10.

  Connects to the Discord Gateway, maintains a heartbeat, handles
  HELLO/READY/RESUMED opcodes, and delivers messages via the REST API.

  ## Config

      config :konsolidator, Konsolidator.Adapters.Discord,
        token: System.get_env("DISCORD_BOT_TOKEN"),
        intents: 33283   # GUILDS | GUILD_MESSAGES | MESSAGE_CONTENT | DIRECT_MESSAGES

  ## Intents

  Default intents (33283) cover:
    * 1  — GUILDS
    * 512 — GUILD_MESSAGES
    * 32768 — MESSAGE_CONTENT (requires privileged intent in dev portal)

  Add `:intents` to your config to override.
  """

  use GenServer
  require Logger

  alias Konsolidator.{Content, Router}
  alias Konsolidator.Adapters.Discord.WS

  @behaviour Konsolidator.Adapter

  @gateway_host "gateway.discord.gg"
  @gateway_path "/?v=10&encoding=json"
  @gateway_port 443
  @api_base "https://discord.com/api/v10"
  @default_intents 33_283

  # Opcodes
  @op_dispatch 0
  @op_heartbeat 1
  @op_identify 2
  @op_resume 6
  @op_hello 10
  @op_heartbeat_ack 11

  @impl Konsolidator.Adapter
  def name, do: :discord

  @impl Konsolidator.Adapter
  def capabilities do
    [:send_text, :edit_text, :delete_message, :send_file, :send_photo,
     :inline_buttons, :url_buttons, :typing_indicator, :reply_to,
     :markdown, :code_blocks, :threads]
  end

  @impl Konsolidator.Adapter
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Konsolidator.Adapter
  def send(adapter, channel_id, content), do: GenServer.call(adapter, {:send, channel_id, content}, 15_000)

  @impl Konsolidator.Adapter
  def edit(adapter, channel_id, ref, content), do: GenServer.call(adapter, {:edit, channel_id, ref, content}, 15_000)

  @impl Konsolidator.Adapter
  def delete(adapter, channel_id, ref), do: GenServer.call(adapter, {:delete, channel_id, ref}, 15_000)

  @impl Konsolidator.Adapter
  def typing(adapter, channel_id, state), do: GenServer.call(adapter, {:typing, channel_id, state}, 5_000)

  @impl Konsolidator.Adapter
  def answer_callback(_adapter, _callback_id, _opts), do: :ok

  @impl true
  def init(opts) do
    state = %{
      token: Keyword.fetch!(opts, :token),
      intents: Keyword.get(opts, :intents, @default_intents),
      ws: nil,
      session_id: nil,
      seq: nil,
      heartbeat_interval: nil,
      hb_ref: nil,
      resume_url: nil
    }
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    host = if state.resume_url do
      state.resume_url
      |> String.replace_prefix("wss://", "")
      |> String.split("/")
      |> hd()
    else
      @gateway_host
    end
    case WS.connect(host, @gateway_port, @gateway_path) do
      {:ok, ws} ->
        send(self(), :recv)
        {:noreply, %{state | ws: ws}}
      {:error, reason} ->
        Logger.error("[Discord] Gateway connection failed: #{inspect(reason)}, retrying in 10s")
        Process.send_after(self(), :reconnect, 10_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:reconnect, state), do: {:noreply, state, {:continue, :connect}}

  @impl true
  def handle_info(:recv, %{ws: nil} = state), do: {:noreply, state}

  @impl true
  def handle_info(:recv, state) do
    case WS.recv(state.ws) do
      {:ok, frame, ws2} ->
        state2 = handle_gateway_event(frame, %{state | ws: ws2})
        send(self(), :recv)
        {:noreply, state2}
      {:error, :closed} ->
        Logger.warning("[Discord] Gateway closed, reconnecting in 5s")
        Process.send_after(self(), :reconnect, 5_000)
        {:noreply, %{state | ws: nil}}
      {:error, reason} ->
        Logger.warning("[Discord] Gateway recv error: #{inspect(reason)}, reconnecting in 5s")
        Process.send_after(self(), :reconnect, 5_000)
        {:noreply, %{state | ws: nil}}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    if state.ws do
      WS.send_json(state.ws, %{op: @op_heartbeat, d: state.seq})
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:send, channel_id, content}, _from, state) do
    body = content_to_body(content)
    url = "#{@api_base}/channels/#{channel_id}/messages"
    reply = case rest_post(state.token, url, body) do
      {:ok, %{"id" => id}} -> {:ok, id}
      {:ok, _} -> {:error, :no_id}
      err -> err
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:edit, channel_id, ref, content}, _from, state) do
    body = content_to_body(content)
    url = "#{@api_base}/channels/#{channel_id}/messages/#{ref}"
    reply = case rest_patch(state.token, url, body) do
      {:ok, _} -> :ok
      err -> err
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, channel_id, ref}, _from, state) do
    url = "#{@api_base}/channels/#{channel_id}/messages/#{ref}"
    reply = case rest_delete(state.token, url) do
      :ok -> :ok
      err -> err
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:typing, channel_id, :on}, _from, state) do
    url = "#{@api_base}/channels/#{channel_id}/typing"
    Req.post(url, headers: auth_headers(state.token), body: "")
    {:reply, :ok, state}
  end

  def handle_call({:typing, _channel_id, :off}, _from, state), do: {:reply, :ok, state}

  ## Gateway event handling

  defp handle_gateway_event(%{"op" => @op_hello, "d" => %{"heartbeat_interval" => interval}}, state) do
    if state.hb_ref, do: Process.cancel_timer(state.hb_ref)
    hb_ref = Process.send_after(self(), :heartbeat, interval)
    payload =
      if state.session_id && state.seq do
        %{op: @op_resume, d: %{token: state.token, session_id: state.session_id, seq: state.seq}}
      else
        %{op: @op_identify, d: %{token: state.token, intents: state.intents,
            properties: %{os: "linux", browser: "konsolidator", device: "konsolidator"}}}
      end
    WS.send_json(state.ws, payload)
    %{state | heartbeat_interval: interval, hb_ref: hb_ref}
  end

  defp handle_gateway_event(%{"op" => @op_heartbeat_ack}, state) do
    if state.hb_ref, do: Process.cancel_timer(state.hb_ref)
    hb_ref = Process.send_after(self(), :heartbeat, state.heartbeat_interval || 41_250)
    %{state | hb_ref: hb_ref}
  end

  defp handle_gateway_event(%{"op" => @op_dispatch, "t" => "READY", "d" => d, "s" => seq}, state) do
    Logger.info("[Discord] Connected as #{get_in(d, ["user", "username"])}")
    %{state | session_id: d["session_id"], seq: seq, resume_url: d["resume_gateway_url"]}
  end

  defp handle_gateway_event(%{"op" => @op_dispatch, "t" => "MESSAGE_CREATE", "d" => msg, "s" => seq}, state) do
    # Ignore bot messages
    unless get_in(msg, ["author", "bot"]) do
      Router.publish_incoming(%{
        source: :discord,
        user_id: msg["channel_id"],
        text: msg["content"] || "",
        ref: msg["id"],
        raw: msg
      })
    end
    %{state | seq: seq}
  end

  defp handle_gateway_event(%{"op" => @op_dispatch, "s" => seq} = _event, state) when not is_nil(seq) do
    %{state | seq: seq}
  end

  defp handle_gateway_event(_event, state), do: state

  ## REST helpers

  defp content_to_body(%Content{} = content) do
    base = if content.text, do: %{content: content.text}, else: %{}
    if content.buttons do
      Map.put(base, :components, [build_action_row(content.buttons)])
    else
      base
    end
  end

  defp build_action_row(rows) do
    buttons = rows |> List.flatten() |> Enum.map(fn btn ->
      if btn.url do
        %{type: 5, label: btn.label, url: btn.url, style: 5}
      else
        %{type: 2, label: btn.label, custom_id: btn.data || btn.label, style: 1}
      end
    end)
    %{type: 1, components: buttons}
  end

  defp auth_headers(token), do: [{"Authorization", "Bot #{token}"}, {"Content-Type", "application/json"}]

  defp rest_post(token, url, body) do
    case Req.post(url, headers: auth_headers(token), json: body) do
      {:ok, %Req.Response{status: s, body: b}} when s in [200, 201] -> {:ok, b}
      {:ok, %Req.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
  end

  defp rest_patch(token, url, body) do
    case Req.patch(url, headers: auth_headers(token), json: body) do
      {:ok, %Req.Response{status: 200, body: b}} -> {:ok, b}
      {:ok, %Req.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
  end

  defp rest_delete(token, url) do
    case Req.delete(url, headers: auth_headers(token)) do
      {:ok, %Req.Response{status: 204}} -> :ok
      {:ok, %Req.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
  end
end
