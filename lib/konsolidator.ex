defmodule Konsolidator do
  @moduledoc """
  Konsolidator — adapter-based multi-messenger routing library for Elixir.

  This is the top-level facade. The interesting things are:
    * `Konsolidator.Adapter` — the behaviour
    * `Konsolidator.Content` / `Konsolidator.Button` — common types
    * `Konsolidator.Router` — PubSub-backed routing
    * `Konsolidator.Adapters.*` — concrete adapters

  Most callers only need:
      Konsolidator.deliver(user_id, content)
      Konsolidator.edit(user_id, ref, content)
      Konsolidator.delete(user_id, ref)
      Konsolidator.typing(user_id, :on | :off)
      Konsolidator.subscribe_incoming()
  """

  alias Konsolidator.{Content, Router}

  @doc """
  Deliver a `Content` to the user. Routed via Phoenix.PubSub to all
  adapters that are subscribed for the given `user_id`.
  """
  @spec deliver(integer() | String.t(), Content.t()) :: :ok
  defdelegate deliver(user_id, content), to: Router

  @doc """
  Edit a previously sent message.
  """
  @spec edit(integer() | String.t(), term(), Content.t()) :: :ok
  defdelegate edit(user_id, ref, content), to: Router

  @doc """
  Delete a previously sent message.
  """
  @spec delete(integer() | String.t(), term()) :: :ok
  defdelegate delete(user_id, ref), to: Router

  @doc """
  Show or hide the typing indicator.
  """
  @spec typing(integer() | String.t(), :on | :off) :: :ok
  defdelegate typing(user_id, state), to: Router

  @doc """
  Subscribe the calling process to all incoming user messages and
  button presses from all active adapters.
  """
  @spec subscribe_incoming() :: :ok
  defdelegate subscribe_incoming(), to: Router
end
