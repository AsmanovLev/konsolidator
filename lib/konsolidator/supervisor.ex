defmodule Konsolidator.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    adapter_modules = Application.get_env(:konsolidator, :adapters, [])

    children =
      Enum.map(adapter_modules, fn mod ->
        # Each adapter module is responsible for its own start_link/1.
        # Configuration lives under config :konsolidator, mod.
        cfg = Application.get_env(:konsolidator, mod, [])
        Supervisor.child_spec({mod, cfg}, id: mod)
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
