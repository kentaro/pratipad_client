defmodule PratipadClientTest do
  use ExUnit.Case
  doctest PratipadClient

  test "greets the world" do
    assert PratipadClient.hello() == :world
  end
end
