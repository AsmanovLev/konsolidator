defmodule Konsolidator.RouterTest do
  use ExUnit.Case, async: false

  alias Konsolidator.{Router, Content, Button}

  describe "deliver/2" do
    test "with empty content is a no-op (no broadcast)" do
      # The application supervisor is started by the test harness via the
      # mix.exs config. If we subscribe and call deliver with empty content,
      # we should NOT receive anything.
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:1")
      :ok = Router.deliver(1, Content.new())
      refute_receive {:deliver, _, _}, 50
    end

    test "with text content broadcasts to subscribers" do
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:42")
      :ok = Router.deliver(42, Content.new(text: "hi"))
      assert_receive {:deliver, 42, %Content{text: "hi"}}, 100
    end

    test "with buttons broadcasts the full content" do
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:7")
      btns = [[%Button{label: "OK", data: "ok"}]]
      :ok = Router.deliver(7, Content.new(text: "Pick", buttons: btns))
      assert_receive {:deliver, 7, %Content{buttons: ^btns}}, 100
    end
  end

  describe "edit/3" do
    test "broadcasts the edit request" do
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:99")
      :ok = Router.edit(99, 12345, Content.new(text: "edited"))
      assert_receive {:edit, 99, 12345, %Content{text: "edited"}}, 100
    end
  end

  describe "delete/2" do
    test "broadcasts the delete request" do
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:8")
      :ok = Router.delete(8, 9999)
      assert_receive {:delete, 8, 9999}, 100
    end
  end

  describe "typing/2" do
    test "broadcasts the typing state" do
      :ok = Phoenix.PubSub.subscribe(Router.pubsub(), "user:5")
      :ok = Router.typing(5, :on)
      assert_receive {:typing, 5, :on}, 100
    end

    test "rejects invalid typing state" do
      # @impl typing/2 uses when guard; invalid state raises FunctionClauseError.
      assert_raise FunctionClauseError, fn -> Router.typing(5, :maybe) end
    end
  end

  describe "topic/1" do
    test "returns user-prefixed string" do
      assert Router.topic(123) == "user:123"
      assert Router.topic("abc") == "user:abc"
    end
  end
end
