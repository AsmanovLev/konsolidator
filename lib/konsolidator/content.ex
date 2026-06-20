defmodule Konsolidator.Content do
  @moduledoc """
  Cross-messenger message content. A `Content` struct describes everything an
  adapter needs to render a single message on its platform.

  Adapters translate this into native format (Telegram HTML, Discord embeds,
  Matrix `m.room.message`, Slack Block Kit, etc.) and back.

  Use `Konsolidator.Content.new/1` to build one.
  """

  @type parse_mode :: :plain | :markdown | :html
  @type t :: %__MODULE__{
          text: String.t() | nil,
          file: Path.t() | nil,
          photo: Path.t() | nil,
          video: Path.t() | nil,
          audio: Path.t() | nil,
          sticker: String.t() | nil,
          buttons: [[Konsolidator.Button.t()]] | nil,
          parse_mode: parse_mode(),
          reply_to: Konsolidator.Adapter.ref() | nil,
          thread: term() | nil,
          silent: boolean()
        }

  defstruct text: nil,
            file: nil,
            photo: nil,
            video: nil,
            audio: nil,
            sticker: nil,
            buttons: nil,
            parse_mode: :plain,
            reply_to: nil,
            thread: nil,
            silent: false

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs
    struct!(__MODULE__, attrs)
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = c) do
    is_nil(c.text) and is_nil(c.file) and is_nil(c.photo) and
      is_nil(c.video) and is_nil(c.audio) and is_nil(c.sticker) and
      is_nil(c.buttons)
  end

  @spec any_media?(t()) :: boolean()
  def any_media?(%__MODULE__{} = c) do
    not (is_nil(c.file) and is_nil(c.photo) and
           is_nil(c.video) and is_nil(c.audio))
  end

  @spec buttons?(t()) :: boolean()
  def buttons?(%__MODULE__{} = c), do: not is_nil(c.buttons)
end
