defmodule Konsolidator.Adapters.Telegram.FormatTest do
  use ExUnit.Case, async: true

  alias Konsolidator.{Content, Button}
  alias Konsolidator.Adapters.Telegram.Format

  test "plain text is HTML-escaped" do
    {text, _opts} = Format.to_html(Content.new(text: "a < b & c > d"))
    assert text == "a &lt; b &amp; c &gt; d"
  end

  test "html parse_mode passes through" do
    {text, opts} = Format.to_html(Content.new(text: "<b>x</b>", parse_mode: :html))
    assert text == "<b>x</b>"
    assert opts[:parse_mode] == "HTML"
  end

  test "markdown parse_mode converts bold/italic/code/links" do
    md = "**b** *i* `c` [l](https://e.com)"
    {text, _} = Format.to_html(Content.new(text: md, parse_mode: :markdown))
    assert text == "<b>b</b> <i>i</i> <code>c</code> <a href=\"https://e.com\">l</a>"
  end

  test "markdown converts fenced code blocks to <pre>" do
    md = "```elixir\nIO.puts \"hi\"\n```"
    {text, _} = Format.to_html(Content.new(text: md, parse_mode: :markdown))
    assert text =~ "<pre>"
    assert text =~ "IO.puts"
  end

  test "silent option translates to disable_notification" do
    {_text, opts} = Format.to_html(Content.new(text: "x", silent: true))
    assert opts[:disable_notification] == true
  end

  test "reply_to translates to reply_to_message_id" do
    {_text, opts} = Format.to_html(Content.new(text: "x", reply_to: 99))
    assert opts[:reply_to_message_id] == 99
  end

  test "thread translates to message_thread_id" do
    {_text, opts} = Format.to_html(Content.new(text: "x", thread: 7))
    assert opts[:message_thread_id] == 7
  end

  test "plain parse_mode still escapes HTML special chars" do
    {text, _} = Format.to_html(Content.new(text: "<script>alert(1)</script>", parse_mode: :plain))
    refute text =~ "<script>"
    assert text =~ "&lt;script&gt;"
  end

  test "returns disable_web_page_preview true" do
    {_text, opts} = Format.to_html(Content.new(text: "x"))
    assert opts[:disable_web_page_preview] == true
  end

  test "to_html/2 accepts a text_override that bypasses content.text" do
    {text, _} = Format.to_html(Content.new(text: "original"), "overridden")
    assert text == "overridden"
  end

  test "markdown_to_html/1 escapes & first so the order is correct" do
    # & < > must be escaped before bold transformation so we don't double-escape
    # entities like &amp;
    text = Format.markdown_to_html("a & b")
    assert text == "a &amp; b"
  end
end
