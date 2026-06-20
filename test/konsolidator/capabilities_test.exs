defmodule Konsolidator.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Konsolidator.Capabilities

  test "all/0 returns the full capability list" do
    caps = Capabilities.all()
    assert :send_text in caps
    assert :edit_text in caps
    assert :delete_message in caps
    assert :send_file in caps
    assert :send_photo in caps
    assert :send_video in caps
    assert :send_audio in caps
    assert :send_sticker in caps
    assert :inline_buttons in caps
    assert :edit_buttons in caps
    assert :url_buttons in caps
    assert :typing_indicator in caps
    assert :reactions in caps
    assert :threads in caps
    assert :reply_to in caps
    assert :forward in caps
    assert :read_receipts in caps
  end

  test "has?/2 returns true if capability is in list" do
    assert Capabilities.has?([:send_text, :edit_text], :send_text)
    refute Capabilities.has?([:send_text], :edit_text)
  end

  test "validate/1 returns :ok if list is subset of known capabilities" do
    assert :ok = Capabilities.validate([:send_text, :edit_text, :delete_message])
  end

  test "validate/1 returns error for unknown capability" do
    assert {:error, {:unknown_capability, :nonsense}} =
             Capabilities.validate([:send_text, :nonsense])
  end

  test "validate/1 returns error for non-atom entries" do
    assert {:error, {:not_atom, "send_text"}} = Capabilities.validate(["send_text"])
  end
end
