defmodule Konsolidator.Registry do
  @moduledoc """
  Process registry for adapter subscriptions.

  Konsolidator uses Phoenix.PubSub for the heavy lifting (delivering content
  to all adapters that care about a `user_id`). On top of that, this thin
  Registry module tracks:

    * `{user_id, channel_atom}` → adapter pid — which adapter instances are
      active for which user on which channel
    * `:incoming` → backend pid — which backend process wants to be notified
      when a new user message arrives

  Most users will not call this directly; it's used by the adapters and
  by `Konsolidator.Incoming`.

  ## Why a custom Registry (and not just Phoenix.PubSub)?

  Phoenix.PubSub is for fan-out broadcast. It does not store the subscriber
  list for a given topic. We need to know "which adapter is listening for
  user 42 on channel :telegram?" — that's a registry, not a broadcast.
  """

  use GenServer

  @name __MODULE__.Server

  defstruct store: nil, refs: %{}

  @doc """
  Starts the global Konsolidator registry. Idempotent.
  """
  def start_link(opts \\ []) do
    case GenServer.start(__MODULE__, opts, name: opts[:name] || @name) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @doc """
  Returns the canonical registry name (the global one).
  """
  @spec name() :: atom()
  def name, do: @name

  @doc """
  Register the calling process for a key under the given registry.

  Key may be `{user_id, channel}` (for adapters) or `:incoming` (for the
  backend listening for user messages).
  """
  @spec register(atom() | pid(), term(), pid()) :: :ok
  def register(registry \\ @name, key, pid \\ self()) do
    GenServer.call(registry, {:register, key, pid})
  end

  @doc """
  Unregister the calling process from the given key.
  """
  @spec unregister(atom() | pid(), term()) :: :ok
  def unregister(registry \\ @name, key) do
    GenServer.call(registry, {:unregister, key})
  end

  @doc """
  Look up all pids registered for `key`.
  """
  @spec lookup(atom() | pid(), term()) :: [{term(), pid()}]
  def lookup(registry \\ @name, key) do
    GenServer.call(registry, {:lookup, key})
  end

  @doc """
  Run a callback with all pids registered under `key`. The callback receives
  a list of `{key, pid}` tuples and may return anything; the return value is
  discarded.
  """
  @spec dispatch(atom() | pid(), term(), ([{term(), pid()}] -> any())) :: :ok
  def dispatch(registry \\ @name, key, callback) when is_function(callback, 1) do
    entries = lookup(registry, key)
    _ = callback.(entries)
    :ok
  end

  @doc """
  Return all keys currently registered.
  """
  @spec keys(atom() | pid()) :: [term()]
  def keys(registry \\ @name) do
    GenServer.call(registry, :keys)
  end

  # GenServer
  def init(_opts) do
    {:ok, %{store: %{}, refs: %{}}}
  end

  def handle_call({:register, key, pid}, _from, state) do
    refs = Map.update(state.refs, pid, MapSet.new([key]), &MapSet.put(&1, key))
    store = Map.update(state.store, key, MapSet.new([pid]), &MapSet.put(&1, pid))
    Process.monitor(pid)
    {:reply, :ok, %{state | store: store, refs: refs}}
  end

  def handle_call({:unregister, key}, _from, state) do
    {removed, store} = Map.pop(state.store, key, MapSet.new())
    {:reply, :ok, %{state | store: store, refs: prune_refs(state.refs, removed)}}
  end

  def handle_call({:lookup, key}, _from, state) do
    case Map.get(state.store, key) do
      nil -> {:reply, [], state}
      pids -> {:reply, Enum.map(pids, &{key, &1}), state}
    end
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.store), state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    refs = Map.get(state.refs, pid, MapSet.new())

    store =
      Enum.reduce(refs, state.store, fn key, acc ->
        case Map.get(acc, key) do
          nil -> acc
          set -> Map.put(acc, key, MapSet.delete(set, pid))
        end
      end)

    {:noreply, %{state | store: store, refs: Map.delete(state.refs, pid)}}
  end

  defp prune_refs(refs, removed_pids) do
    Enum.reduce(refs, refs, fn {pid, keys}, acc ->
      if MapSet.member?(removed_pids, pid) and MapSet.size(keys) == 0,
        do: Map.delete(acc, pid),
        else: acc
    end)
  end
end
