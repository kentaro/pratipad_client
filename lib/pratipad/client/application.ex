defmodule Pratipad.Client.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    [
      strategy: :one_for_one,
      name: Pratipad.Client.Supervisor
    ]
    |> DynamicSupervisor.start_link()
  end
end
