defmodule Examples.Client.Push do
  use Pratipad.Client, mode: :push, backward_enabled: true
  alias Pratipad.Client

  @impl Client.Push
  def push_message(_opts) do
    "[push] Hi, it's #{DateTime.utc_now} now!"
  end

  @impl Client.Backward
  def backward_message(_opts) do
    Logger.info("got :backward_message")
  end
end
