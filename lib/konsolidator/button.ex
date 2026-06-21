defmodule Konsolidator.Button do
  @moduledoc """
  Cross-messenger inline button. A button is either:
    * a **callback** button with `data` (the platform sends it back when pressed), or
    * a **url** button with `url` (the platform opens it in browser).

  Exactly one of `data` or `url` must be set. A button without an action is invalid.
  """

  @type style :: :default | :positive | :negative | :primary | :secondary
  @type t :: %__MODULE__{
          label: String.t(),
          data: String.t() | nil,
          url: String.t() | nil,
          style: style()
        }

  defstruct label: nil, data: nil, url: nil, style: :default

  @spec new(String.t(), keyword() | String.t()) :: t()
  def new(label, opts \\ [])

  def new(label, data) when is_binary(data) do
    %__MODULE__{label: label, data: data}
  end

  def new(label, opts) when is_list(opts) do
    %__MODULE__{
      label: label,
      data: Keyword.get(opts, :data),
      url: Keyword.get(opts, :url),
      style: Keyword.get(opts, :style, :default)
    }
  end

  @spec callback?(t()) :: boolean()
  def callback?(%__MODULE__{} = b), do: not is_nil(b.data)

  @spec url?(t()) :: boolean()
  def url?(%__MODULE__{} = b), do: not is_nil(b.url)

  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{label: ""}), do: {:error, :empty_label}

  def validate(%__MODULE__{data: d, url: u}) when not is_nil(d) and not is_nil(u),
    do: {:error, :both_data_and_url}

  def validate(%__MODULE__{data: nil, url: nil}), do: {:error, :no_action}
  def validate(%__MODULE__{}), do: :ok
end
