defmodule Konsolidator.Adapters.Telegram.AdapterTest do
  use ExUnit.Case, async: false

  alias Konsolidator.{Content, Button, Router, Registry}
  alias Konsolidator.Adapters.Telegram

  setup do
    # The application supervisor is started by mix test automatically.
    # We use a private PubSub topic for incoming events so we don't leak.
    :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "incoming")

    # Start the adapter under test.
    captured = :ets.new(:captured_requests, [:public, :named_table])
    :ets.delete_all_objects(captured)

    request_fn = fn url, params ->
      :ets.insert(captured, {url, params})
      body = pick_response(url, params)
      {:ok, body}
    end

    start_opts = [token: "TEST_TOKEN", long_poll_timeout: 0, request_fn: request_fn]

    {:ok, pid} =
      case Telegram.start_link(start_opts) do
        {:ok, p} -> {:ok, p}
        {:error, {:already_started, p}} -> {:ok, p}
      end

    %{pid: pid, captured: captured, request_fn: request_fn}
  end

  test "send/3 with text posts to send_message and returns message_id", %{captured: cap} do
    assert {:ok, 12345} = Telegram.send(Telegram, 42, Content.new(text: "hi"))

    [{url, params}] = :ets.tab2list(cap)
    assert url == "https://api.telegram.org/botTEST_TOKEN/send_message"
    assert {_, 42} = List.keyfind(params, :chat_id, 0)
    assert {_, "hi"} = List.keyfind(params, :text, 0)
  end

  test "send/3 with a callback button includes reply_markup", %{captured: cap} do
    content =
      Content.new(
        text: "Pick:",
        buttons: [[%Button{label: "Yes", data: "yes"}]]
      )

    assert {:ok, 12345} = Telegram.send(Telegram, 42, content)
    [{_, params}] = :ets.tab2list(cap)
    {_, markup} = List.keyfind(params, :reply_markup, 0)
    assert markup["inline_keyboard"] == [[%{"text" => "Yes", "callback_data" => "yes"}]]
  end

  test "send/3 with a url button includes url field in reply_markup", %{captured: cap} do
    content =
      Content.new(
        text: "Visit:",
        buttons: [[%Button{label: "Open", url: "https://example.com"}]]
      )

    assert {:ok, 12345} = Telegram.send(Telegram, 42, content)
    [{_, params}] = :ets.tab2list(cap)
    {_, markup} = List.keyfind(params, :reply_markup, 0)
    assert markup["inline_keyboard"] == [[%{"text" => "Open", "url" => "https://example.com"}]]
  end

  test "edit/4 posts to edit_message_text", %{captured: cap} do
    :ets.delete_all_objects(cap)
    content = Content.new(text: "edited", buttons: [[%Button{label: "v", data: "v"}]])
    assert :ok = Telegram.edit(Telegram, 42, 999, content)

    [{url, params}] = :ets.tab2list(cap)
    assert url =~ "edit_message_text"
    assert {_, 999} = List.keyfind(params, :message_id, 0)
  end

  test "delete/3 posts to delete_message", %{captured: cap} do
    :ets.delete_all_objects(cap)
    assert :ok = Telegram.delete(Telegram, 42, 999)
    [{url, params}] = :ets.tab2list(cap)
    assert url =~ "delete_message"
    assert {_, 999} = List.keyfind(params, :message_id, 0)
  end

  test "typing/3 with :on posts send_chat_action typing", %{captured: cap} do
    :ets.delete_all_objects(cap)
    assert :ok = Telegram.typing(Telegram, 42, :on)
    [{url, params}] = :ets.tab2list(cap)
    assert url =~ "send_chat_action"
    assert {_, "typing"} = List.keyfind(params, :action, 0)
  end

  test "typing/3 with :off is a no-op" do
    assert :ok = Telegram.typing(Telegram, 42, :off)
  end

  test "answer_callback/3 posts to answer_callback_query" do
    assert :ok = Telegram.answer_callback(Telegram, "cb-1", text: "Got it")
  end

  ## Helpers

  defp pick_response(url, _params) do
    cond do
      String.contains?(url, "send_message") -> send_message_response()
      String.contains?(url, "edit_message_text") -> edit_message_response()
      String.contains?(url, "delete_message") -> delete_message_response()
      String.contains?(url, "send_chat_action") -> %{"ok" => true, "result" => true}
      String.contains?(url, "answer_callback_query") -> %{"ok" => true, "result" => true}
      String.contains?(url, "get_updates") -> %{"ok" => true, "result" => []}
      true -> %{"ok" => true, "result" => nil}
    end
  end

  defp send_message_response, do: %{"ok" => true, "result" => %{"message_id" => 12345, "chat" => %{"id" => 42}}}
  defp edit_message_response, do: %{"ok" => true, "result" => %{"message_id" => 12346, "chat" => %{"id" => 42}}}
  defp delete_message_response, do: %{"ok" => true, "result" => true}
end
