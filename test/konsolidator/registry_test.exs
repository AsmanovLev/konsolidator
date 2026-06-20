defmodule Konsolidator.RegistryTest do
  use ExUnit.Case

  alias Konsolidator.Registry

  setup do
    name = :"RegistryTest_#{System.unique_integer([:positive])}"
    {:ok, pid} = Registry.start_link(name: name)
    %{reg: name, pid: pid}
  end

  test "register/2 and lookup/2 round-trip", %{reg: reg} do
    me = self()
    assert :ok = Registry.register(reg, {:adapter, 1, :telegram}, me)
    assert [{{:adapter, 1, :telegram}, ^me}] = Registry.lookup(reg, {:adapter, 1, :telegram})
  end

  test "lookup/2 returns [] for unknown entry", %{reg: reg} do
    assert [] = Registry.lookup(reg, {:adapter, 999, :telegram})
  end

  test "registered process receives dispatch", %{reg: reg} do
    me = self()
    Registry.register(reg, :incoming, me)

    assert :ok =
             Registry.dispatch(reg, :incoming, fn entries -> send(self(), {:got, entries}) end)

    assert_received {:got, [incoming: ^me]}
  end

  test "unregister/1 removes the entry", %{reg: reg} do
    Registry.register(reg, :topic, self())
    Registry.unregister(reg, :topic)
    assert [] = Registry.lookup(reg, :topic)
  end

  test "register/3 supports adapter/user/channel triple", %{reg: reg} do
    Registry.register(reg, {:adapter, 42, :telegram}, self())
    assert [_] = Registry.lookup(reg, {:adapter, 42, :telegram})
  end
end
