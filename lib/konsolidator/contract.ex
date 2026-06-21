defmodule Konsolidator.Contract do
  @moduledoc """
  Contract test macros for Konsolidator adapters.

  Use this in your adapter's test file to ensure it implements the
  mandatory parts of the contract correctly:

      defmodule Konsolidator.Adapters.MyApp.AdapterTest do
        use Konsolidator.Contract
      end

  This injects the standard test cases. Adapters must override the
  helpers to provide their own HTTP stubs, fixtures, and module references.

  Required overrides (set as module attributes on the test module):

      @adapter Konsolidator.Adapters.MyApp
      @setup_adapter fn -> ... end   # returns {:ok, pid} or similar
      @teardown_adapter fn -> ... end

  This file documents the contract; see the Telegram adapter test for
  a full working example.
  """

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case

      # Each test is a placeholder; concrete adapter test modules override
      # them or provide their own setup that exercises the behaviour.
      test "adapter declares a name" do
        assert is_atom(@adapter.name())
      end

      test "adapter declares capabilities as a list of atoms" do
        caps = @adapter.capabilities()
        assert is_list(caps)
        assert Enum.all?(caps, &is_atom/1)
        assert Konsolidator.Capabilities.validate(caps) == :ok
      end

      test "adapter start_link/1 returns {:ok, pid}" do
        {:ok, pid} = @setup_adapter.()
        assert is_pid(pid)
        @teardown_adapter.(pid)
      end
    end
  end
end
