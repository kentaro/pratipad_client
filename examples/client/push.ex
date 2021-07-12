defmodule Examples.Client.Push do
  use Pratipad.Client, mode: :push, backward_enabled: true
  alias Pratipad.Client

  @impl Client.Push
  def push_message() do
    "[push] Hi, it's #{DateTime.utc_now} now!"
  end

  @impl Client.Backward
  def backward_message(message) do
    Logger.info("backward_message: #{inspect(message)}")
  end
end
