defmodule Konsolidator.Adapters.MAX do
  @moduledoc """
  MAX Bot API adapter (https://botapi.max.ru).

  Uses HTTP long-poll `GET /updates` with a `marker` cursor, similar to
  Telegram's `getUpdates` offset pattern.

  ## Config

      config :konsolidator, Konsolidator.Adapters.MAX,
        token: System.get_env("MAX_BOT_TOKEN"),
        base_url: "https://botapi.max.ru"   # optional
  """

  use GenServer
  require Logger

  alias Konsolidator.{Content, Router}

  @behaviour Konsolidator.Adapter

  @default_base_url "https://botapi.max.ru"
  @poll_timeout 30

  @impl Konsolidator.Adapter
  def name, do: :max

  @impl Konsolidator.Adapter
  def capabilities do
    [:send_text, :edit_text, :delete_message, :send_photo, :send_file,
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
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      marker: nil
    }
    {:ok, state, {:continue, :start_poll}}
  end

  @impl true
  def handle_continue(:start_poll, state) do
    send(self(), :poll)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case do_poll(state) do
      {:ok, updates, new_marker} ->
        Enum.each(updates, &handle_update(&1, state))
        send(self(), :poll)
        {:noreply, %{state | marker: new_marker}}
      {:error, reason} ->
        Logger.warning("[MAX] Poll error: #{inspect(reason)}, retrying in 5s")
        Process.send_after(self(), :poll, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:send, user_id, content}, _from, state) do
    body = build_message_body(content)
    url = "#{state.base_url}/messages?access_token=#{state.token}&user_id=#{user_id}"
    reply = case Req.post(url, json: body) do
      {:ok, %Req.Response{status: s, body: %{"message" => %{"id" => id}}}} when s in [200, 201] ->
        {:ok, id}
      {:ok, %Req.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:edit, _user_id, ref, content}, _from, state) do
    body = build_message_body(content)
    url = "#{state.base_url}/messages/#{ref}?access_token=#{state.token}"
    reply = case Req.patch(url, json: body) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, _user_id, ref}, _from, state) do
    url = "#{state.base_url}/messages/#{ref}?access_token=#{state.token}"
    reply = case Req.delete(url) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:typing, user_id, :on}, _from, state) do
    url = "#{state.base_url}/chats/#{user_id}/actions?access_token=#{state.token}"
    Req.post(url, json: %{action: "typing_on"})
    {:reply, :ok, state}
  end

  def handle_call({:typing, _user_id, :off}, _from, state), do: {:reply, :ok, state}

  defp do_poll(state) do
    params = [access_token: state.token, timeout: @poll_timeout]
    params = if state.marker, do: params ++ [marker: state.marker], else: params
    url = "#{state.base_url}/updates?" <> URI.encode_query(params)
    case Req.get(url, receive_timeout: (@poll_timeout + 5) * 1_000) do
      {:ok, %Req.Response{status: 200, body: %{"updates" => updates, "marker" => marker}}} ->
        {:ok, updates, marker}
      {:ok, %Req.Response{status: 200, body: %{"updates" => updates}}} ->
        {:ok, updates, state.marker}
      {:ok, %Req.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}
      {:error, r} -> {:error, r}
    end
  end

  defp handle_update(%{"update_type" => "message_created", "message" => msg}, _state) do
    user_id = get_in(msg, ["sender", "user_id"]) || get_in(msg, ["recipient", "chat_id"])
    Router.publish_incoming(%{
      source: :max,
      user_id: user_id,
      text: get_in(msg, ["body", "text"]) || "",
      ref: msg["id"],
      raw: msg
    })
  end
  defp handle_update(%{"update_type" => "message_callback", "callback" => cb}, _state) do
    user_id = get_in(cb, ["user", "user_id"])
    Router.publish_incoming(%{
      source: :max,
      user_id: user_id,
      button_data: get_in(cb, ["payload"]) || "",
      callback_id: cb["callback_id"],
      ref: get_in(cb, ["message", "id"]),
      raw: cb
    })
  end
  defp handle_update(_other, _state), do: :ok

  defp build_message_body(%Content{} = content) do
    text_part = if content.text && content.text != "", do: %{text: content.text}, else: %{}
    buttons_part = if content.buttons, do: %{attachments: [build_buttons(content.buttons)]}, else: %{}
    Map.merge(text_part, buttons_part)
  end

  defp build_buttons(rows) do
    buttons = Enum.map(rows, fn row ->
      Enum.map(row, fn btn ->
        if btn.url do
          %{type: "link", url: btn.url, text: btn.label}
        else
          %{type: "callback", payload: btn.data, text: btn.label}
        end
      end)
    end)
    %{type: "inline_keyboard", payload: %{buttons: buttons}}
  end
end
