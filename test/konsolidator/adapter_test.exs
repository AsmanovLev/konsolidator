defmodule Konsolidator.AdapterTest do
  use ExUnit.Case, async: true

  defmodule DummyAdapter do
    @behaviour Konsolidator.Adapter

    @impl Konsolidator.Adapter
    def name, do: :dummy

    @impl Konsolidator.Adapter
    def capabilities,
      do: [
        :send_text,
        :edit_text,
        :delete_message,
        :send_file,
        :send_photo,
        :send_video,
        :send_audio,
        :inline_buttons,
        :edit_buttons,
        :url_buttons,
        :typing_indicator,
        :reply_to,
        :on_update,
        :on_callback,
        :answer_callback
      ]

    @impl Konsolidator.Adapter
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

    @impl Konsolidator.Adapter
    def send(_adapter, _user_id, _content), do: {:ok, :sent}

    @impl Konsolidator.Adapter
    def edit(_adapter, _user_id, _ref, _content), do: :ok

    @impl Konsolidator.Adapter
    def delete(_adapter, _user_id, _ref), do: :ok

    @impl Konsolidator.Adapter
    def typing(_adapter, _user_id, _state), do: :ok

    @impl Konsolidator.Adapter
    def answer_callback(_adapter, _callback_id, _opts), do: :ok

    use GenServer
    @impl true
    def init(_opts), do: {:ok, %{}}
    @impl true
    def handle_call(_, _, s), do: {:reply, :ok, s}
  end

  test "behaviour has all expected callbacks" do
    callbacks = Konsolidator.Adapter.behaviour_info(:callbacks)
    assert {:name, 0} in callbacks
    assert {:capabilities, 0} in callbacks
    assert {:start_link, 1} in callbacks
    assert {:send, 3} in callbacks
    assert {:edit, 4} in callbacks
    assert {:delete, 3} in callbacks
    assert {:typing, 3} in callbacks
    assert {:answer_callback, 3} in callbacks
  end

  test "an adapter module that uses @behaviour compiles and exports name/0" do
    assert function_exported?(DummyAdapter, :name, 0)
    assert DummyAdapter.name() == :dummy
  end

  test "capable?/2 returns true when adapter declares the capability" do
    assert Konsolidator.Adapter.capable?(DummyAdapter, :send_text)
    assert Konsolidator.Adapter.capable?(DummyAdapter, :edit_text)
  end

  test "capable?/2 returns false for an undeclared capability" do
    refute Konsolidator.Adapter.capable?(DummyAdapter, :reactions)
    refute Konsolidator.Adapter.capable?(DummyAdapter, :payments)
  end
end
