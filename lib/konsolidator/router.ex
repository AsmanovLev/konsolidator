defmodule Konsolidator.Router do
  @moduledoc """
  Routes outgoing and incoming events between the backend and adapters
  using Phoenix.PubSub.

  ## Outgoing (backend → adapters)

  `Konsolidator.deliver/2`, `Konsolidator.edit/3`, `Konsolidator.delete/2`,
  `Konsolidator.typing/2` are implemented as `Phoenix.PubSub.broadcast/3`
  under the topic `\"user:<USER_ID>\"`. Each adapter subscribes to the
  topics for the user_ids it cares about, then dispatches to its native API.

  ## Incoming (user → backend)

  Adapters publish to `\"incoming\"` topic. The backend subscribes once.

  ## Routing decisions

  Adapters decide whether to actually act on a broadcast. An adapter
  without the right `capability` for a `Content` payload (e.g. no
  `:send_video` for a Telegram message that contains video) is responsible
  for falling back — typically: send a text note with a link to the file.
  """

  # Suppress the false-positive warning about no user_id in this module.

  alias Konsolidator.{Content, Registry}

  @pubsub __MODULE__.PubSub

  @doc """
  Returns the Phoenix.PubSub instance used by Konsolidator.
  """
  @spec pubsub() :: module()
  def pubsub, do: @pubsub

  @doc """
  Broadcast a new content payload to all adapters handling `user_id`.

  Empty content (no text and no media and no buttons) is a no-op.
  """
  @spec deliver(integer() | String.t(), Content.t()) :: :ok
  def deliver(user_id, %Content{} = content) do
    if Content.empty?(content) do
      :ok
    else
      Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:deliver, user_id, content})
    end
  end

  @doc """
  Broadcast a request to edit a previously sent message.
  """
  @spec edit(integer() | String.t(), Konsolidator.Adapter.ref(), Content.t()) :: :ok
  def edit(user_id, ref, %Content{} = content) do
    Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:edit, user_id, ref, content})
  end

  @doc """
  Broadcast a request to delete a previously sent message.
  """
  @spec delete(integer() | String.t(), Konsolidator.Adapter.ref()) :: :ok
  def delete(user_id, ref) do
    Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:delete, user_id, ref})
  end

  @doc """
  Broadcast a typing indicator state change.
  """
  @spec typing(integer() | String.t(), :on | :off) :: :ok
  def typing(user_id, state) when state in [:on, :off] do
    Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:typing, user_id, state})
  end

  @doc """
  Subscribe the calling process to all incoming events from all adapters.
  The backend process should call this once at startup.
  """
  @spec subscribe_incoming() :: :ok
  def subscribe_incoming do
    Phoenix.PubSub.subscribe(@pubsub, "incoming")
    Registry.register(Konsolidator.Registry.name(), :incoming)
    :ok
  end

  @doc """
  Subscribe the calling process to outgoing events for a specific user_id.
  Adapters call this in their `handle_continue/2` after registration.
  """
  @spec subscribe_user(integer() | String.t()) :: :ok
  def subscribe_user(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(user_id))
  end

  @doc """
  Publish an incoming event from an adapter. Adapters call this when a
  user message or button press arrives.
  """
  @spec publish_incoming(map()) :: :ok
  def publish_incoming(payload) when is_map(payload) do
    Phoenix.PubSub.broadcast(@pubsub, "incoming", {:incoming, payload})
  end

  @doc """
  Topic for a given user_id. Internal — used by the `deliver/2`, `edit/3`,
  `delete/2` functions above.
  """
  @spec topic(integer() | String.t()) :: String.t()
  def topic(user_id), do: "user:#{user_id}"
end
