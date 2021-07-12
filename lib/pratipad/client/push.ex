defmodule Pratipad.Client.Push do
  @callback push_message(opts :: list) :: term
end
