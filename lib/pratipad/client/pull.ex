defmodule Pratipad.Client.Pull do
  @callback pull_message(opts :: list) :: term
end
