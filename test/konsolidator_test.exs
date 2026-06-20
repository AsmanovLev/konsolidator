defmodule KonsolidatorTest do
  use ExUnit.Case, async: true

  alias Konsolidator.{Content, Button}

  test "module loads and exposes core structs" do
    assert %Content{} = Content.new()
    assert %Button{} = Button.new("x", "y")
  end
end
