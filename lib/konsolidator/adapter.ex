defmodule Konsolidator.Adapter do
  @moduledoc """
  Behaviour every adapter must implement. An adapter is a single named module
  (e.g. `Konsolidator.Adapters.Telegram`) that knows how to talk to ONE
  messenger platform.

  Each adapter exposes:
    * `name/0` — atom identifying the platform (`:telegram`, `:discord`, …)
    * `capabilities/0` — list of capability atoms from `Konsolidator.Capabilities`
    * `start_link/1` — GenServer entry point
    * `send/3` — deliver new content, returns `{:ok, ref}` with native message id
    * `edit/4` — edit a previously sent message
    * `delete/3` — delete a previously sent message
    * `typing/3` — show or hide the typing indicator
    * `answer_callback/3` — ack an inline button press (toast or alert)

  ## Why "self" as first arg?

  Adapters run as GenServers under `Konsolidator.Supervisor`. The first
  argument is always the adapter module name itself, so the consumer can
  call the same callback against any adapter without caring about its
  internal pid.

  ## Implementing a new adapter

  Add a new `Konsolidator.Adapters.<Name>` module that:
    1. Declares `@behaviour Konsolidator.Adapter`
    2. Implements all 8 callbacks above
    3. Returns a native `ref()` (e.g. Telegram message_id, Discord snowflake, VK post_id)

  See `Konsolidator.Adapters.Telegram` for a working reference.
  """

  alias Konsolidator.{Content, Capabilities}

  @typedoc """
  Platform-native message reference. Concrete shape is per-adapter:
    * Telegram — integer message_id
    * Discord — string snowflake
    * VK — integer post_id
    * MAX — string message id
    * Matrix — string event id
    * Slack — string ts
  """
  @type ref :: term()

  @typedoc "Adapter module that implements this behaviour."
  @type adapter :: module()

  @type user_id :: integer() | String.t()
  @type callback_id :: String.t() | term()
  @type typing_state :: :on | :off

  @callback name() :: atom()
  @callback capabilities() :: [Capabilities.capability()]
  @callback start_link(keyword()) :: GenServer.on_start()

  @callback send(adapter(), user_id(), Content.t()) ::
              {:ok, ref()} | {:error, term()}

  @callback edit(adapter(), user_id(), ref(), Content.t()) ::
              :ok | {:error, term()}

  @callback delete(adapter(), user_id(), ref()) :: :ok | {:error, term()}

  @callback typing(adapter(), user_id(), typing_state()) :: :ok

  @callback answer_callback(adapter(), callback_id(), keyword()) ::
              :ok | {:error, term()}

  @optional_callbacks []

  @doc """
  Returns true if the adapter declares the given capability.
  """
  @spec capable?(adapter(), Capabilities.capability()) :: boolean()
  def capable?(adapter, cap) when is_atom(adapter) and is_atom(cap) do
    Capabilities.has?(adapter.capabilities(), cap)
  rescue
    _ -> false
  end

  @doc """
  Returns the list of adapters that are currently compiled in.
  """
  @spec known() :: [adapter()]
  def known do
    Application.get_env(:konsolidator, :adapters, [])
  end
end
