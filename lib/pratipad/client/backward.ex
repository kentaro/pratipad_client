defmodule Pratipad.Client.Backward do
  @callback backward_message(message :: any()) :: term
end
