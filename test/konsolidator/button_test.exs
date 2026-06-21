defmodule Konsolidator.ButtonTest do
  use ExUnit.Case, async: true

  alias Konsolidator.Button

  test "new/3 builds a callback button" do
    b = Button.new("Click", "data")
    assert b.label == "Click"
    assert b.data == "data"
    assert b.url == nil
    assert b.style == :default
  end

  test "new/3 with url builds a url button (data must be nil)" do
    b = Button.new("Visit", url: "https://example.com")
    assert b.label == "Visit"
    assert b.url == "https://example.com"
    assert b.data == nil
  end

  test "callback?/1 returns true when data is set" do
    assert Button.callback?(%Button{label: "x", data: "d"})
  end

  test "callback?/1 returns false when data is nil" do
    refute Button.callback?(%Button{label: "x"})
  end

  test "url?/1 returns true when url is set" do
    assert Button.url?(%Button{label: "x", url: "u"})
  end

  test "url?/1 returns false when url is nil" do
    refute Button.url?(%Button{label: "x"})
  end

  test "validate/1 rejects empty label" do
    assert {:error, :empty_label} = Button.validate(%Button{label: ""})
  end

  test "validate/1 rejects both data and url set" do
    assert {:error, :both_data_and_url} =
             Button.validate(%Button{label: "x", data: "d", url: "u"})
  end

  test "validate/1 rejects neither data nor url set" do
    assert {:error, :no_action} = Button.validate(%Button{label: "x"})
  end

  test "validate/1 accepts a callback button" do
    assert :ok = Button.validate(%Button{label: "x", data: "d"})
  end

  test "validate/1 accepts a url button" do
    assert :ok = Button.validate(%Button{label: "x", url: "u"})
  end
end
