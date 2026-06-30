defmodule Konsolidator.Adapters.VK do
  @moduledoc """
  VK Communities adapter using the Bots Long Poll API.

  ## Config

      config :konsolidator, Konsolidator.Adapters.VK,
        token: System.get_env("VK_TOKEN"),
        group_id: System.get_env("VK_GROUP_ID"),
        api_version: "5.131"
  """

  use GenServer
  require Logger

  alias Konsolidator.{Content, Router}

  @behaviour Konsolidator.Adapter

  @api_base "https://api.vk.com/method"
  @default_version "5.131"
  @poll_wait 25

  @impl Konsolidator.Adapter
  def name, do: :vk

  @impl Konsolidator.Adapter
  def capabilities do
    [:send_text, :edit_text, :delete_message, :send_file, :send_photo,
     :inline_buttons, :url_buttons, :typing_indicator, :reply_to]
  end

  @impl Konsolidator.Adapter
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Konsolidator.Adapter
  def send(adapter, user_id, content), do: GenServer.call(adapter, {:send, user_id, content}, 15_000)

  @impl Konsolidator.Adapter
  def edit(adapter, user_id, ref, content), do: GenServer.call(adapter, {:edit, user_id, ref, content}, 15_000)

  @impl Konsolidator.Adapter
  def delete(adapter, user_id, ref), do: GenServer.call(adapter, {:delete, user_id, ref}, 15_000)

  @impl Konsolidator.Adapter
  def typing(adapter, user_id, state), do: GenServer.call(adapter, {:typing, user_id, state}, 5_000)

  @impl Konsolidator.Adapter
  def answer_callback(_adapter, _callback_id, _opts), do: :ok

  @impl true
  def init(opts) do
    state = %{
      token: Keyword.fetch!(opts, :token),
      group_id: opts |> Keyword.fetch!(:group_id) |> to_string(),
      version: Keyword.get(opts, :api_version, @default_version),
      lp_server: nil, lp_key: nil, lp_ts: nil
    }
    {:ok, state, {:continue, :init_long_poll}}
  end

  @impl true
  def handle_continue(:init_long_poll, state) do
    case fetch_lp_server(state) do
      {:ok, server, key, ts} ->
        send(self(), :poll)
        {:noreply, %{state | lp_server: server, lp_key: key, lp_ts: ts}}
      {:error, reason} ->
        Logger.error("[VK] Failed to get Long Poll server: #{inspect(reason)}, retrying in 10s")
        Process.send_after(self(), :reinit, 10_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:reinit, state), do: {:noreply, state, {:continue, :init_long_poll}}

  @impl true
  def handle_info(:poll, state) do
    case do_poll(state) do
      {:ok, updates, new_ts} ->
        Enum.each(updates, &handle_update(&1, state))
        send(self(), :poll)
        {:noreply, %{state | lp_ts: new_ts}}
      {:failed, code} when code in [1, 2, 3] ->
        Logger.warning("[VK] Long Poll failed=#{code}, re-initialising")
        {:noreply, state, {:continue, :init_long_poll}}
      {:error, reason} ->
        Logger.warning("[VK] Long Poll error: #{inspect(reason)}, retrying in 5s")
        Process.send_after(self(), :poll, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:send, user_id, content}, _from, state) do
    params = %{
      user_id: user_id,
      message: content.text || "",
      random_id: :rand.uniform(1_000_000_000),
      v: state.version,
      access_token: state.token
    }
    params = if content.buttons, do: Map.put(params, :keyboard, Jason.encode!(build_keyboard(content.buttons))), else: params
    reply = case api_post("messages.send", params) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      {:ok, _} -> {:error, :no_message_id}
      err -> err
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:edit, user_id, ref, content}, _from, state) do
    params = %{peer_id: user_id, message_id: ref, message: content.text || "", v: state.version, access_token: state.token}
    reply = case api_post("messages.edit", params) do {:ok, _} -> :ok; err -> err end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, user_id, ref}, _from, state) do
    params = %{peer_id: user_id, cmids: ref, delete_for_all: 1, v: state.version, access_token: state.token}
    reply = case api_post("messages.delete", params) do {:ok, _} -> :ok; err -> err end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:typing, user_id, :on}, _from, state) do
    api_post("messages.setActivity", %{peer_id: user_id, type: "typing", v: state.version, access_token: state.token})
    {:reply, :ok, state}
  end

  def handle_call({:typing, _user_id, :off}, _from, state), do: {:reply, :ok, state}

  defp fetch_lp_server(state) do
    case api_post("groups.getLongPollServer", %{group_id: state.group_id, v: state.version, access_token: state.token}) do
      {:ok, %{"server" => server, "key" => key, "ts" => ts}} -> {:ok, server, key, ts}
      {:ok, other} -> {:error, {:unexpected, other}}
      err -> err
    end
  end

  defp do_poll(state) do
    url = "#{state.lp_server}?act=a_check&key=#{state.lp_key}&ts=#{state.lp_ts}&wait=#{@poll_wait}"
    case Req.get(url, receive_timeout: (@poll_wait + 5) * 1_000) do
      {:ok, %Req.Response{status: 200, body: %{"failed" => code}}} -> {:failed, code}
      {:ok, %Req.Response{status: 200, body: %{"ts" => new_ts, "updates" => updates}}} -> {:ok, updates, new_ts}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_update(%{"type" => "message_new", "object" => %{"message" => msg}}, _state) do
    Router.publish_incoming(%{source: :vk, user_id: msg["peer_id"] || msg["from_id"],
      text: msg["text"] || "", ref: msg["id"], raw: msg})
  end
  defp handle_update(%{"type" => "message_event", "object" => obj}, _state) do
    Router.publish_incoming(%{source: :vk, user_id: obj["peer_id"],
      button_data: Jason.encode!(obj["payload"] || %{}),
      callback_id: "#{obj["event_id"]}", ref: obj["conversation_message_id"], raw: obj})
  end
  defp handle_update(_other, _state), do: :ok

  defp build_keyboard(nil), do: nil
  defp build_keyboard(rows) do
    %{"one_time" => false, "buttons" => Enum.map(rows, fn row ->
      Enum.map(row, fn btn ->
        if btn.url do
          %{"action" => %{"type" => "open_link", "link" => btn.url, "label" => btn.label}}
        else
          %{"action" => %{"type" => "callback", "payload" => Jason.encode!(%{data: btn.data}), "label" => btn.label}}
        end
      end)
    end)}
  end

  defp api_post(method, params) do
    case Req.post("#{@api_base}/#{method}", form: Enum.to_list(params)) do
      {:ok, %Req.Response{status: 200, body: %{"response" => r}}} -> {:ok, r}
      {:ok, %Req.Response{status: 200, body: %{"error" => e}}} -> {:error, {:vk_error, e["error_code"], e["error_msg"]}}
      {:ok, %Req.Response{status: s}} -> {:error, {:http, s}}
      {:error, r} -> {:error, r}
    end
  end
end
