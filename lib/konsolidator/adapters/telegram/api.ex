defmodule Konsolidator.Adapters.Telegram.Api do
  @moduledoc """
  Thin HTTP client for the Telegram Bot API. Uses `Req` (HTTP/2 over Finch).

  The bot's token is passed per-call so the module is pure: no global state,
  no GenServer. This makes it trivial to mock in tests by swapping the
  request function.

  ## Error handling

  Telegram returns JSON like:
      {"ok": true,  "result": <message object>}
      {"ok": false, "description": "...", "error_code": 400}

  We translate:
    * ok=true  → `{:ok, decoded_result}` (caller is responsible for knowing
                  the shape — message_id, file_id, list of updates, etc.)
    * ok=false → `{:error, %{description: ..., code: ...}}`
    * HTTP failure → `{:error, {:http, status_code, body}}`
  """

  require Logger

  @type method ::
          :send_message
          | :edit_message_text
          | :delete_message
          | :send_chat_action
          | :answer_callback_query
          | :send_photo
          | :send_document
          | :send_video
          | :send_audio
          | :send_voice
          | :send_sticker
          | :get_updates
          | :get_me

  @type opts :: keyword()

  @doc """
  Base URL for the Telegram Bot API: `https://api.telegram.org/bot<TOKEN>/<method>`.
  """
  @spec base_url(String.t(), method()) :: String.t()
  def base_url(token, method) do
    "https://api.telegram.org/bot#{token}/#{method}"
  end

  @doc """
  Issue a JSON request to the Telegram API.

  ## Parameters

    * `token` — bot token from @BotFather
    * `method` — atom like `:send_message`
    * `params` — keyword list of params (encoded as form-data when a file
      is present, otherwise as JSON body)
    * `request_fn` — optional `Req` request function. Defaults to `Req.post/2`.
      Pass a stub in tests.

  ## Returns

    * `{:ok, term()}` — the `result` field from a successful API call
    * `{:error, %{description: String.t(), code: integer()}}` — API-level error
    * `{:error, {:http, integer(), term()}}` — HTTP-level error
  """
  @spec call(String.t(), method(), opts(), (String.t(), keyword() -> {:ok, map()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
  def call(token, method, params \\ [], request_fn \\ &default_post/2) do
    url = base_url(token, method)

    case request_fn.(url, params) do
      {:ok, %{"ok" => true, "result" => result}} -> {:ok, result}
      {:ok, %{"ok" => false, "description" => desc} = body} ->
        {:error, %{description: desc, code: body["error_code"], parameters: body["parameters"]}}

      {:error, %Req.TransportError{} = err} ->
        Logger.warning("Telegram #{method} transport error: #{inspect(err.reason)}")
        {:error, {:http, :transport, err.reason}}

      {:error, %Finch.Error{reason: reason}} ->
        Logger.warning("Telegram #{method} finch error: #{inspect(reason)}")
        {:error, {:http, :finch, reason}}

      other ->
        Logger.warning("Telegram #{method} unexpected response: #{inspect(other)}")
        {:error, {:http, :unexpected, other}}
    end
  end

  # Default request function. Encodes params as multipart form-data if any
  # param value is a binary path that exists on disk, otherwise as JSON body.
  defp default_post(url, params) do
    has_file =
      Enum.any?(params, fn {_, v} -> is_binary(v) and File.regular?(v) end)

    req_opts =
      if has_file do
        [form: params]
      else
        [json: Map.new(params)]
      end

    Req.post(url, req_opts)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{body: body}} -> {:ok, body || %{"ok" => false}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Tag a path as a file to upload. Req detects binary values that look like
  existing file paths and treats them as multipart fields.
  """
  @spec file(Path.t()) :: Path.t()
  def file(path) when is_binary(path), do: path
end
