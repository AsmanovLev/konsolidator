defmodule Konsolidator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Konsolidator.Registry,
      {Phoenix.PubSub, name: Konsolidator.Router.pubsub()},
      Konsolidator.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Konsolidator.Supervisor.Root]
    Supervisor.start_link(children, opts)
  end
end
