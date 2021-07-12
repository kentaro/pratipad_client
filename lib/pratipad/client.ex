defmodule Pratipad.Client do
  @doc """
  A base module for implementing the client for Pratipad.

  ## Options

  The client process implemented using this module communicates to the receiver process of Pratipad via message passings each other.

  If Pratipad runs on `:pull` mode and the demand it has is not fully met,
  it sends `:pull_message` message to the client via the receiver.

  If the producer runs on `:push` mode, you can freely push a message
  regardless of whether the Broadway producer has demand or not.

  If the settings defined for Pratipad supports bidirectional dataflow,
  it sends `:backward_message` message to the client via the receiver.

  ```
  defmodule ExamplesClient do
    use Pratipad.Client

    @impl GenServer
    def handle_cast(:pull_message, state) do
      Logger.debug("received: :pull_message")
      GenServer.cast(state.receiver, {:send_message, "I'm alive!"})

      {:noreply, state}
    end

    @impl GenServer
    def handle_cast({:push_message, message}, state) do
      GenServer.cast(state.receiver, {:push_message, message})
      {:noreply, state}
    end

    def start(opts \\ []) do
      [
        {__MODULE__, opts}
      ]
      |> Supervisor.start_link(
        strategy: :one_for_one,
        name: ExamplesClient.Supervisor
      )
    end

    def push_message(message) do
      GenServer.cast(__MODULE__, {:push_message, message})
    end
  end
  ```
  """

  defmacro __using__(opts) do
    quote do
      @behaviour Pratipad.Client

      mode = unquote(opts[:mode]) || :push
      backward_enabled = uncuote(opts[:backward_enbaled]) || false

      case mode do
        :push -> @callback push_message(opts \\ []) :: term
        :pull -> @callback pull_message(opts \\ []) :: term
        _ -> raise("Invalid `mode` option: #{mode}")
      end

      if backward_enabled do
        @callback backward_message(opts \\ []) :: term
      end

      use GenServer
      require Logger

      @default_forwarder_name :pratipad_forwarder
      @default_backwarer_name :pratipad_backwarder
      @default_max_retry_count 10

      @impl GenServer
      def init(opts \\ []) do
        forwarder_name = opts[:forwarder_name] || @default_forwarder_name
        backwarder_name = opts[:backwarder_name] || @default_backwarder_name
        max_retry_count = opts[:max_retry_count] || @default_max_retry_count
        bidirectional = !!opts[:bidirectional]

        forwarder = connect_to_receiver(forwarder_name, max_retry_count)

        backwarder =
          if bidirectional do
            connect_to_receiver(backwarder_name, max_retry_count)
          else
            nil
          end

        {:ok,
         %{
           max_retry_count: max_retry_count,
           receivers: %{
             forwarder: %{
               name: forwarder_name,
               pid: forwarder
             },
             backwarder: %{
               name: backwarder_name,
               pid: backwarder
             }
           },
           bidirectional: bidirectional
         }}
      end

      def start(opts \\ []) do
        DynamicSupervisor.start_child(Pratipad.Client.Supervisor, {
          Pratipad.Handler.Message
        })
      end

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl GenServer
      def handle_cast({:push_message, opts \\ []}, state) do
        Logger.debug("received: :push_message")
        message = push_message(opts)

        GenServer.cast(state.receivers.forwarder.pid, {:push_message, message})
        {:noreply, state}
      end

      @impl GenServer
      def handle_cast({:pull_message, opts \\ []}, state) do
        Logger.debug("received: :pull_message")
        message = pull_message(opts)

        GenServer.cast(state.receivers.forwarder.pid, {:send_message, message})
        {:noreply, state}
      end

      @impl GenServer
      def handle_cast({:backward_message, opts \\ []}, state) do
        Logger.debug("received: :backward_message")
        message = backward_message(opts)
        {:noreply, state}
      end

      @impl GenServer
      def handle_info({:DOWN, _, _, pid, reason}, state) do
        Logger.error("Server is down: #{reason}")

        anormal_receiver =
          case state.receivers do
            %{forwarder: %{pid: ^pid}} -> state.receivers.forwarder
            %{backwarder: %{pid: ^pid}} -> state.receivers.backwarder
          end

        receiver = connect_to_receiver(anormal_receiver.name, state.max_retry_count)

        {:noreply, %{state | receiver: receiver}}
      end

      @impl GenServer
      def terminate(reason, state) do
        Logger.error("Client is terminating: #{inspect(reason)}")
      end

      defp connect_to_receiver(receiver_name, retry_count) do
        receiver = try_connect_to_receiver(receiver_name, retry_count)

        GenServer.call(receiver, :register)
        Logger.info("Register this client to #{inspect(receiver)}")

        # To reboot this process when the receiver process terminates
        Process.monitor(receiver)

        receiver
      end

      defp try_connect_to_receiver(receiver_name, retry_count) do
        if retry_count > 0 do
          :global.sync()
          receiver = :global.whereis_name(receiver_name)

          if receiver == :undefined do
            Logger.debug("Waiting for the receiver is up.")
            Process.sleep(500)
            try_connect_to_receiver(receiver_name, retry_count - 1)
          else
            receiver
          end
        else
          raise("Couldn't connect to #{receiver_name}")
        end
      end
    end
  end
end
