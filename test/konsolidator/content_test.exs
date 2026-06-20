defmodule Konsolidator.ContentTest do
  use ExUnit.Case, async: true

  alias Konsolidator.Content

  test "new/0 returns a struct with sensible defaults" do
    c = Content.new()
    assert c.text == nil
    assert c.file == nil
    assert c.photo == nil
    assert c.video == nil
    assert c.audio == nil
    assert c.buttons == nil
    assert c.parse_mode == :plain
    assert c.reply_to == nil
    assert c.silent == false
    assert c.thread == nil
  end

  test "new/1 with attrs merges over defaults" do
    c = Content.new(text: "hi", parse_mode: :markdown)
    assert c.text == "hi"
    assert c.parse_mode == :markdown
  end

  test "empty?/1 returns true when no payload is set" do
    assert Content.empty?(Content.new())
  end

  test "empty?/1 returns false when text is set" do
    refute Content.empty?(Content.new(text: "x"))
  end

  test "empty?/1 returns false when file is set" do
    refute Content.empty?(Content.new(file: "x"))
  end

  test "empty?/1 returns false when photo is set" do
    refute Content.empty?(Content.new(photo: "x"))
  end

  test "empty?/1 returns false when buttons are set" do
    refute Content.empty?(Content.new(buttons: [[]]))
  end

  test "any_media?/1 returns true for file/photo/video/audio" do
    assert Content.any_media?(%Content{file: "f"})
    assert Content.any_media?(%Content{photo: "p"})
    assert Content.any_media?(%Content{video: "v"})
    assert Content.any_media?(%Content{audio: "a"})
  end

  test "any_media?/1 returns false for text-only" do
    refute Content.any_media?(%Content{text: "hi"})
    refute Content.any_media?(%Content{})
  end

  test "buttons?/1 returns true when buttons are set" do
    assert Content.buttons?(%Content{buttons: [[]]})
  end

  test "buttons?/1 returns false when buttons are nil" do
    refute Content.buttons?(%Content{buttons: nil})
  end
end
