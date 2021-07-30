defmodule Pratipad.Client.Backward do
  @callback forward_message(message :: any()) :: term
end
