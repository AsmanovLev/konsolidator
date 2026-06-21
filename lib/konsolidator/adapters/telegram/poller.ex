defmodule Konsolidator.Adapters.Telegram.Poller do
  @moduledoc """
  Long-poll loop for `getUpdates`. Sends each update to the parent
  GenServer (the adapter) for processing. Restarts on error.
  """

  use GenServer
  require Logger

  alias Konsolidator.Adapters.Telegram.Api

  def start_link(parent, token, timeout, allowed_updates) do
    GenServer.start_link(__MODULE__, {parent, token, timeout, allowed_updates})
  end

  @impl true
  def init({parent, token, timeout, allowed_updates}) do
    state = %{
      parent: parent,
      token: token,
      timeout: timeout,
      allowed_updates: allowed_updates,
      offset: 0
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state) do
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_poll(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll, do: Process.send_after(self(), :poll, 0)

  defp do_poll(%{token: token, timeout: timeout, allowed_updates: au, offset: offset} = state) do
    params = [timeout: timeout, allowed_updates: au, offset: offset]

    case Api.call(token, :get_updates, params) do
      {:ok, updates} when is_list(updates) ->
        Enum.each(updates, fn update ->
          send(state.parent, {:update, update})
        end)

        new_offset =
          case List.last(updates) do
            nil -> offset
            %{"update_id" => id} -> id + 1
          end

        schedule_poll()
        %{state | offset: new_offset}

      {:error, reason} ->
        Logger.warning("Telegram getUpdates error: #{inspect(reason)}")
        # Back off on error: 5s.
        Process.send_after(self(), :poll, 5_000)
        state
    end
  end
end
