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
    alias Pratipad.Client

    @impl Client
    def push_message(_opts) do
      "message to be pushed"
    end

    @impl Client
    def pull_message(_opts) do
      "message to be pulled"
    end

    @impl Client
    def backward_message(_opts) do
      # do something along with the backward message
    end
  end
  ```
  """

  defmacro __using__(opts \\ []) do
    quote do
      alias Pratipad.Client

      mode = unquote(opts[:mode]) || :push
      backward_enabled = unquote(opts[:backward_enabled]) || false

      case mode do
        :push -> @behaviour Client.Push
        :pull -> @behaviour Client.Pull
        _ -> raise("Invalid `mode` option: #{mode}")
      end

      if backward_enabled do
        @behaviour Client.Backward
        @backward_enabled true
      end

      use GenServer
      require Logger

      @default_forwarder_name :pratipad_forwarder_input
      @default_backwarder_name :pratipad_backwarder_output
      @default_max_retry_count 10

      @impl GenServer
      def init(opts \\ []) do
        forwarder_name = opts[:forwarder_name] || @default_forwarder_name
        backwarder_name = opts[:backwarder_name] || @default_backwarder_name
        max_retry_count = opts[:max_retry_count] || @default_max_retry_count

        forwarder = connect_to_receiver(forwarder_name, max_retry_count)

        backwarder =
          if @backward_enabled do
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
           }
         }}
      end

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      if mode == :push do
        @impl GenServer
        def handle_cast(:push_message, state) do
          Logger.debug("received: :push_message")
          message = push_message()

          GenServer.cast(state.receivers.forwarder.pid, {:push_message, message})
          {:noreply, state}
        end
      end

      if mode == :pull do
        @impl GenServer
        def handle_cast(:pull_message, state) do
          Logger.debug("received: :pull_message")
          message = pull_message()

          GenServer.cast(state.receivers.forwarder.pid, {:send_message, message})
          {:noreply, state}
        end
      end

      if backward_enabled do
        @impl GenServer
        def handle_cast({:backward_message, message}, state) do
          Logger.debug("received: :backward_message")
          message = backward_message(message)
          {:noreply, state}
        end
      end

      @impl GenServer
      def handle_info({:DOWN, _, _, pid, reason}, state) do
        Logger.error("Server is down: #{reason}")

        {receiver_type, anormal_receiver} =
          case state.receivers do
            %{forwarder: %{pid: ^pid}} -> {:forwarder, state.receivers.forwarder}
            %{backwarder: %{pid: ^pid}} -> {:backwarder, state.receivers.backwarder}
          end

        receiver = connect_to_receiver(anormal_receiver.name, state.max_retry_count)

        receivers =
          Map.put(state.receivers, receiver_type, %{
            name: anormal_receiver.name,
            pid: receiver
          })

        {:noreply, %{state | receivers: receivers}}
      end

      @impl GenServer
      def terminate(reason, state) do
        Logger.error("Client is terminating: #{inspect(reason)}")
      end

      defp connect_to_receiver(receiver_name, retry_count) do
        receiver = try_connect_to_receiver_with_retry_count(receiver_name, retry_count)

        GenServer.call(receiver, :register)
        Logger.info("Register this client to #{inspect(receiver)}")

        # To reboot this process when the receiver process terminates
        Process.monitor(receiver)

        receiver
      end

      defp try_connect_to_receiver_with_retry_count(receiver_name, :infinity) do
        receiver = try_connect_to_receiver(receiver_name)

        if receiver == :undefined do
          Logger.debug("Waiting for the receiver is up.")
          Process.sleep(500)
          try_connect_to_receiver_with_retry_count(receiver_name, :infinity)
        else
          receiver
        end
      end

      defp try_connect_to_receiver_with_retry_count(receiver_name, retry_count)
           when retry_count >= 0 do
        receiver =
          if retry_count > 0 do
            receiver = try_connect_to_receiver(receiver_name)
          else
            raise("Couldn't connect to #{receiver_name}")
          end

        if receiver == :undefined do
          Logger.debug("Waiting for the receiver is up.")
          Process.sleep(500)
          try_connect_to_receiver_with_retry_count(receiver_name, retry_count - 1)
        else
          receiver
        end
      end

      defp try_connect_to_receiver(receiver_name) do
        :global.sync()
        :global.whereis_name(receiver_name)
      end
    end
  end
end
