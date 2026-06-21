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

  @method_names %{
    send_message: "sendMessage",
    edit_message_text: "editMessageText",
    delete_message: "deleteMessage",
    send_chat_action: "sendChatAction",
    answer_callback_query: "answerCallbackQuery",
    send_photo: "sendPhoto",
    send_document: "sendDocument",
    send_video: "sendVideo",
    send_audio: "sendAudio",
    send_voice: "sendVoice",
    send_sticker: "sendSticker",
    get_updates: "getUpdates",
    get_me: "getMe"
  }

  @doc """
  Base URL for the Telegram Bot API: `https://api.telegram.org/bot<TOKEN>/<method>`.
  """
  @spec base_url(String.t(), method()) :: String.t()
  def base_url(token, method) do
    "https://api.telegram.org/bot#{token}/#{method_name(method)}"
  end

  @spec method_name(method()) :: String.t()
  def method_name(method) do
    @method_names[method] || Atom.to_string(method)
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
  # When :konsolidator, :proxy is set (e.g. "socks5h://127.0.0.1:10808"),
  # uses :httpc with SOCKS5 support instead of Req.
  defp default_post(url, params) do
    has_file =
      Enum.any?(params, fn {_, v} -> is_binary(v) and File.regular?(v) end)

    proxy = Application.get_env(:konsolidator, :proxy, "")

    if proxy != "" do
      httpc_post(url, params, has_file, proxy)
    else
      req_post(url, params, has_file)
    end
  end

  defp req_post(url, params, has_file) do
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

  # For SOCKS5 proxy, use curl as subprocess. :httpc is broken on OTP 29
  # (missing :http_util.timestamp/0). curl handles SOCKS natively.
  # We write the JSON body to a temp file and use --data-binary @file
  # because Windows System.cmd corrupts non-ASCII (emojis) on the command line.
  defp httpc_post(url, params, _has_file, proxy) do
    {_, proxy_port} = parse_socks_url(proxy)
    proxy_host = proxy |> String.replace("socks5h://", "") |> String.replace("socks5://", "") |> String.split(":") |> hd()

    json_body = Jason.encode!(Map.new(params, fn {k, v} -> {k, v} end))
    tmp = Path.join(System.tmp_dir!(), "konsolidator_#{System.unique_integer([:positive])}.json")
    File.write!(tmp, json_body)

    args =
       ["--proxy", "socks5h://#{proxy_host}:#{proxy_port}",
        "-s", "-m", "35",
        "-H", "Content-Type: application/json",
        "--data-binary", "@" <> tmp,
        url]

    try do
      case safe_curl(args) do
        {:ok, output} ->
          case Jason.decode(output) do
            {:ok, map} -> {:ok, map}
            _ -> {:error, {:decode_error, output}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    after
      File.rm(tmp)
    end
  end

  defp safe_curl(args) do
    try do
      case System.cmd("curl", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, code} -> {:error, {:curl_error, code, output}}
      end
    rescue
      e in ErlangError -> {:error, {:curl_not_found, e.reason}}
    end
  end

  defp parse_socks_url(url) do
    url
    |> String.replace("socks5h://", "")
    |> String.replace("socks5://", "")
    |> String.split(":")
    |> then(fn [host, port] -> {String.to_charlist(host), String.to_integer(port)} end)
  end

  @doc """
  Tag a path as a file to upload. Req detects binary values that look like
  existing file paths and treats them as multipart fields.
  """
  @spec file(Path.t()) :: Path.t()
  def file(path) when is_binary(path), do: path
end
