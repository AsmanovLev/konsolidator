defmodule Konsolidator.Capabilities do
  @moduledoc """
  Capability flags an adapter can declare. The full list is the union of what
  the top messengers support.

  Mandatory (all adapters must support):
    `:send_text`, `:edit_text`, `:delete_message`, `:send_file`, `:send_photo`,
    `:inline_buttons`, `:edit_buttons`, `:url_buttons`, `:typing_indicator`,
    `:reply_to`, `:on_update`, `:on_callback`, `:answer_callback`

  Optional (depend on platform):
    `:send_video`, `:send_audio`, `:send_sticker`, `:reactions`, `:threads`,
    `:forward`, `:read_receipts`, `:markdown`, `:html`, `:rich_text`,
    `:code_blocks`, `:file_upload_50mb`, `:bot_commands`, `:persistent_keyboard`,
    `:payments`, `:polls`
  """

  @type capability :: atom()

  @all [
    :send_text,
    :edit_text,
    :delete_message,
    :send_file,
    :send_photo,
    :send_video,
    :send_audio,
    :send_sticker,
    :inline_buttons,
    :edit_buttons,
    :url_buttons,
    :typing_indicator,
    :reactions,
    :threads,
    :reply_to,
    :forward,
    :read_receipts,
    :markdown,
    :html,
    :rich_text,
    :code_blocks,
    :file_upload_50mb,
    :bot_commands,
    :persistent_keyboard,
    :payments,
    :polls
  ]

  @spec all() :: [capability()]
  def all, do: @all

  @spec has?([capability()], capability()) :: boolean()
  def has?(caps, cap) when is_list(caps) and is_atom(cap), do: cap in caps
  def has?(_, _), do: false

  @spec validate([capability()]) :: :ok | {:error, term()}
  def validate(caps) when is_list(caps) do
    cond do
      Enum.any?(caps, fn c -> not is_atom(c) end) ->
        offending = Enum.find(caps, fn c -> not is_atom(c) end)
        {:error, {:not_atom, offending}}

      true ->
        case Enum.find(caps, fn c -> c not in @all end) do
          nil -> :ok
          unknown -> {:error, {:unknown_capability, unknown}}
        end
    end
  end

  def validate(_), do: {:error, :not_a_list}
end
