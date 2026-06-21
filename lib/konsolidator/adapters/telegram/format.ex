defmodule Konsolidator.Adapters.Telegram.Format do
  @moduledoc """
  Converts Konsolidator `Content` payloads to the subset of HTML that
  the Telegram Bot API accepts as `parse_mode: "HTML"`.

  Telegram-supported tags: `<b>`, `<i>`, `<u>`, `<s>`, `<strike>`, `<del>`,
  `<a href="...">`, `<code>`, `<pre>`. Plus `<tg-spoiler>`,
  `<tg-emoji emoji-id="...">`.

  For markdown parse_mode we translate the most common syntax:
    * `**bold**` → `<b>bold</b>`
    * `*italic*` → `<i>italic</i>`
    * `` `code` `` → `<code>code</code>`
    * ```` ```lang\ncode\n``` ```` → `<pre>code</pre>`
    * `[label](url)` → `<a href="url">label</a>`
  """

  @doc """
  Render Konsolidator content as Telegram HTML. The optional `text_override`
  bypasses `content.text` (used when an adapter is re-rendering on edit
  and wants to inject a marker).

  Returns `{html, opts}` where `opts` is a keyword list of extra API params
  (e.g. `parse_mode: "HTML"`, `disable_web_page_preview: true`).
  """
  @spec to_html(Konsolidator.Content.t(), String.t() | nil) :: {String.t(), keyword()}
  def to_html(%Konsolidator.Content{} = content, text_override \\ nil) do
    text = text_override || content.text || ""

    {rendered_text, mode} =
      case content.parse_mode do
        :html -> {text, "HTML"}
        :markdown -> {markdown_to_html(text), "HTML"}
        :plain -> {escape_html(text), "HTML"}
        :text -> {text, nil}
        nil -> {text, nil}
        _ -> {text, nil}
      end

    opts = [disable_web_page_preview: true, disable_notification: content.silent]
    opts = if mode, do: Keyword.put(opts, :parse_mode, mode), else: opts

    opts =
      opts
      |> maybe_put(:reply_to_message_id, content.reply_to)
      |> maybe_put(:message_thread_id, content.thread)

    {rendered_text, opts}
  end

  @doc """
  Convert markdown-flavored text to Telegram-flavoured HTML.

  Conservative: only the syntax listed in the moduledoc. Anything else is
  left as-is. Call `escape_html/1` first to handle stray `&`, `<`, `>`.
  """
  @spec markdown_to_html(String.t()) :: String.t()
  def markdown_to_html(text) when is_binary(text) do
    text
    |> escape_html()
    |> convert_code_blocks()
    |> convert_inline_code()
    |> convert_links()
    |> convert_bold()
    |> convert_italic()
  end

  @doc """
  Escape `<`, `>`, `&`, `"` so the text is safe inside HTML.
  """
  @spec escape_html(String.t()) :: String.t()
  def escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)

  # Convert ```lang\n...\n``` to <pre>...</pre>.
  defp convert_code_blocks(text) do
    Regex.replace(~r/```[a-zA-Z0-9_-]*\n([\s\S]*?)\n```/, text, fn _, body ->
      "<pre>#{body}</pre>"
    end)
  end

  # Convert `inline` to <code>inline</code> (not greedy).
  defp convert_inline_code(text) do
    Regex.replace(~r/`([^`\n]+)`/, text, "<code>\\1</code>")
  end

  # Convert [label](url) to <a href="url">label</a>.
  defp convert_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _, label, url ->
      "<a href=\"#{url}\">#{label}</a>"
    end)
  end

  # Convert **bold** to <b>bold</b>.
  defp convert_bold(text) do
    Regex.replace(~r/\*\*([^*\n]+)\*\*/, text, "<b>\\1</b>")
  end

  # Convert *italic* to <i>italic</i> (single asterisk, not double).
  defp convert_italic(text) do
    Regex.replace(~r/(?<![\*])\*(?!\*)([^*\n]+)(?<![\*])\*(?!\*)/, text, "<i>\\1</i>")
  end
end
