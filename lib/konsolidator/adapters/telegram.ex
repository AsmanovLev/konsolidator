defmodule Konsolidator.Adapters.Telegram do
  @moduledoc """
  Telegram Bot API adapter. One GenServer per bot, started under
  `Konsolidator.Supervisor`.

  ## What this adapter does

    1. Long-polls `getUpdates` in a loop (background process)
    2. Translates incoming messages and button presses into Konsolidator
       incoming events on the `"incoming"` topic
    3. Subscribes to `Phoenix.PubSub` "user:USER_ID" topics and translates
       Konsolidator outgoing events into Telegram API calls

  ## Config

      config :konsolidator, Konsolidator.Adapters.Telegram,
        token: "123456:ABC...",
        long_poll_timeout: 30,
        allowed_updates: ["message", "callback_query"],
        base_url: "https://api.telegram.org"   # optional, default

  Add to your supervision tree via:

      config :konsolidator, :adapters, [Konsolidator.Adapters.Telegram]
  """

  use GenServer
  require Logger

  alias Konsolidator.{Content, Button, Router}
  alias Konsolidator.Adapters.Telegram.{Api, Format, Poller}

  @behaviour Konsolidator.Adapter

  @default_long_poll 30
  @default_base_url "https://api.telegram.org"

  @impl Konsolidator.Adapter
  def name, do: :telegram

  @impl Konsolidator.Adapter
  def capabilities do
    [
      :send_text,
      :edit_text,
      :delete_message,
      :send_file,
      :send_photo,
      :send_video,
      :send_audio,
      :send_sticker,
      :inline_buttons,
      :edit_buttons,
      :url_buttons,
      :typing_indicator,
      :reactions,
      :threads,
      :reply_to,
      :forward,
      :markdown,
      :html,
      :rich_text,
      :code_blocks,
      :file_upload_50mb,
      :bot_commands
    ]
  end

  @impl Konsolidator.Adapter
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Konsolidator.Adapter
  def send(adapter, user_id, content) do
    GenServer.call(adapter, {:send, user_id, content}, 15_000)
  end

  @impl Konsolidator.Adapter
  def edit(adapter, user_id, ref, content) do
    GenServer.call(adapter, {:edit, user_id, ref, content}, 15_000)
  end

  @impl Konsolidator.Adapter
  def delete(adapter, user_id, ref) do
    GenServer.call(adapter, {:delete, user_id, ref}, 15_000)
  end

  @impl Konsolidator.Adapter
  def typing(adapter, user_id, state) do
    GenServer.call(adapter, {:typing, user_id, state}, 5_000)
  end

  @impl Konsolidator.Adapter
  def answer_callback(adapter, callback_id, opts) do
    GenServer.call(adapter, {:answer_callback, callback_id, opts}, 5_000)
  end

  @doc "Platform-specific: pin a message."
  def pin_message(adapter, chat_id, message_id) do
    GenServer.call(adapter, {:pin_message, chat_id, message_id}, 10_000)
  end

  ## GenServer

  @impl true
  def init(opts) do
    state = %{
      token: Keyword.fetch!(opts, :token),
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      long_poll_timeout: Keyword.get(opts, :long_poll_timeout, @default_long_poll),
      allowed_updates: Keyword.get(opts, :allowed_updates, ["message", "callback_query"]),
      last_update_id: 0,
      request_fn: Keyword.get(opts, :request_fn)
    }
    {:ok, state, {:continue, :start_poller}}
  end

  @impl true
  def handle_continue(:start_poller, state) do
    # Subscribe to the global incoming topic so we can publish events.
    Router.subscribe_incoming()

    # Register ourselves for any user_id on :telegram channel.
    Konsolidator.Registry.register(Konsolidator.Registry.name(), {:adapter, :any, :telegram}, self())

    # Start the long-poll loop in a linked process.
    {:ok, poller_pid} = Poller.start_link(self(), state.token, state.long_poll_timeout, state.allowed_updates)
    Process.monitor(poller_pid)

    # Subscribe to all user topics by NOT subscribing to a specific one
    # (PubSub broadcast reaches only subscribers). Instead, the backend will
    # call our `send/3` etc. directly. For routing from Konsolidator.deliver/2
    # broadcasts, the consumer (e.g. Smago) calls Konsolidator.Adapter.send/3
    # with our module as the first argument.
    {:noreply, state}
  end

  @impl true
  def handle_call({:send, user_id, content}, _from, state) do
    {text, opts} = Format.to_html(content)
    reply_markup = build_reply_markup(content.buttons)

    params =
      [{:chat_id, user_id}, {:text, text}] ++
        opts ++
        if(reply_markup, do: [reply_markup: reply_markup], else: [])

    result =
      cond do
        content.file -> send_file(state, user_id, content, params)
        content.photo -> send_photo(state, user_id, content, params)
        content.video -> send_video(state, user_id, content, params)
        content.audio -> send_audio(state, user_id, content, params)
        content.sticker -> send_sticker(state, user_id, content, params)
        true -> do_call(state, :send_message, params)
      end

    {:reply, unwrap_send(result), state}
  end

  def handle_call({:edit, user_id, ref, content}, _from, state) do
    {text, opts} = Format.to_html(content)
    reply_markup = build_reply_markup(content.buttons)

    params =
      [{:chat_id, user_id}, {:message_id, ref}, {:text, text}] ++
        opts ++
        if(reply_markup, do: [reply_markup: reply_markup], else: [])

    reply =
      case do_call(state, :edit_message_text, params) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end

    {:reply, reply, state}
  end

  def handle_call({:delete, user_id, ref}, _from, state) do
    reply =
      case do_call(state, :delete_message, [chat_id: user_id, message_id: ref]) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:typing, user_id, :on}, _from, state) do
    reply =
      case do_call(state, :send_chat_action, [chat_id: user_id, action: "typing"]) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end

    {:reply, reply, state}
  end

  def handle_call({:typing, _user_id, :off}, _from, state) do
    # Telegram has no "stop typing" action. The chat action expires after 5s.
    {:reply, :ok, state}
  end

  def handle_call({:pin_message, chat_id, message_id}, _from, state) do
    reply =
      case do_call(state, :pin_chat_message, [chat_id: chat_id, message_id: message_id]) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end
    {:reply, reply, state}
  end

  def handle_call({:answer_callback, callback_id, opts}, _from, state) do
    params =
      [{:callback_query_id, callback_id}] ++
        if(opts[:text], do: [text: opts[:text]], else: []) ++
        if(opts[:show_alert], do: [show_alert: true], else: [])

    reply =
      case do_call(state, :answer_callback_query, params) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end

    {:reply, reply, state}
  end

  # Wrapper that uses either the injected request_fn (tests) or the default.
  defp do_call(%{request_fn: nil, token: token}, method, params),
    do: Api.call(token, method, params)

  defp do_call(%{request_fn: f, token: token}, method, params),
    do: Api.call(token, method, params, f)

  @impl true
  def handle_info({:update, update}, state) do
    handle_update(update, state)
    {:noreply, %{state | last_update_id: max(state.last_update_id, update["update_id"] || 0)}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Telegram poller died: #{inspect(reason)}, restarting")
    {:ok, new_pid} = Poller.start_link(self(), state.token, state.long_poll_timeout, state.allowed_updates)
    Process.monitor(new_pid)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Helpers

  defp handle_update(%{"message" => msg}, _state) do
    text = msg["text"] || msg["caption"] || ""
    user_id = msg["chat"]["id"]
    message_id = msg["message_id"]

    Router.publish_incoming(%{
      source: :telegram,
      user_id: user_id,
      text: text,
      ref: message_id,
      raw: msg
    })
  end

  defp handle_update(%{"edited_message" => msg}, _state) do
    # Treat edits as incoming too; consumer can dedupe.
    text = msg["text"] || msg["caption"] || ""
    user_id = msg["chat"]["id"]
    message_id = msg["message_id"]

    Router.publish_incoming(%{
      source: :telegram,
      user_id: user_id,
      text: text,
      ref: message_id,
      raw: msg,
      kind: :edit
    })
  end

  defp handle_update(%{"callback_query" => cb}, _state) do
    user_id = get_in(cb, ["message", "chat", "id"])
    data = cb["data"]
    cb_id = cb["id"]

    Router.publish_incoming(%{
      source: :telegram,
      user_id: user_id,
      callback_id: cb_id,
      button_data: data,
      ref: get_in(cb, ["message", "message_id"]),
      raw: cb
    })
  end

  defp handle_update(_other, _state), do: :ok

  defp build_reply_markup(nil), do: nil
  defp build_reply_markup(rows) when is_list(rows) do
    %{
      "inline_keyboard" =>
        Enum.map(rows, fn row ->
          Enum.map(row, fn %Button{label: l, data: d, url: u} ->
            cond do
              u -> %{"text" => l, "url" => u}
              d -> %{"text" => l, "callback_data" => d}
              true -> %{"text" => l}
            end
          end)
        end)
    }
  end

  defp send_file(state, _user_id, %Content{} = content, base_params) do
    params = base_params ++ [document: Api.file(content.file), caption: content.text || ""]
    do_call(state, :send_document, params)
  end

  defp send_photo(state, _user_id, %Content{} = content, base_params) do
    params = base_params ++ [photo: Api.file(content.photo), caption: content.text || ""]
    do_call(state, :send_photo, params)
  end

  defp send_video(state, _user_id, %Content{} = content, base_params) do
    params = base_params ++ [video: Api.file(content.video), caption: content.text || ""]
    do_call(state, :send_video, params)
  end

  defp send_audio(state, _user_id, %Content{} = content, base_params) do
    params = base_params ++ [audio: Api.file(content.audio), caption: content.text || ""]
    do_call(state, :send_audio, params)
  end

  defp send_sticker(state, user_id, %Content{} = content, _base_params) do
    do_call(state, :send_sticker, [chat_id: user_id, sticker: content.sticker])
  end

  # Translate Telegram API responses to a single integer message_id ref.
  defp unwrap_send({:ok, %{"message_id" => id}}), do: {:ok, id}
  defp unwrap_send({:ok, _}), do: {:error, :no_message_id}
  defp unwrap_send({:error, _} = err), do: err
end
