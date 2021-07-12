defmodule Examples.Client do
  use Pratipad.Client, mode: :pull, backward_enabled: true
  alias Pratipad.Client

  @impl Client.Pull
  def pull_message(_opts) do
    "[pull] Hi, it's #{DateTime.utc_now} now!"
  end

  @impl Client.Backward
  def backward_message(_opts) do
    Logger.info("got :backward_message")
  end
end
