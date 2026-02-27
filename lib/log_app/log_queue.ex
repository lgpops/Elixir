defmodule LogApp.LogQueue do
  @moduledoc """
  Ordered ingestion queue for incoming logs.

  The queue guarantees FIFO processing for all requests received by this node:
  Cowboy ingress enqueues, this GenServer persists to Postgres, then broadcasts
  to PubSub.
  """

  use GenServer
  require Logger

  @type enqueue_result :: {:ok, struct()} | {:error, term()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(String.t(), String.t(), map(), timeout()) :: enqueue_result
  def enqueue(level, workflow_id, message, timeout \\ 5_000) do
    GenServer.call(__MODULE__, {:enqueue, level, workflow_id, message}, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, :queue_timeout}

    :exit, {:noproc, _} ->
      {:error, :queue_unavailable}

    :exit, reason ->
      Logger.error("Queue enqueue failed: #{inspect(reason)}")
      {:error, :queue_unavailable}
  end

  @impl true
  def init(_opts) do
    Logger.info("LogQueue started")

    {:ok,
     %{
       queue: :queue.new(),
       next_sequence: 1,
       processing?: false
     }}
  end

  @impl true
  def handle_call({:enqueue, level, workflow_id, message}, from, state) do
    sequence = state.next_sequence
    item = {sequence, from, %{level: level, workflow_id: workflow_id, message: message}}
    queue = :queue.in(item, state.queue)
    next_state = %{state | queue: queue, next_sequence: sequence + 1}

    if next_state.processing? do
      {:noreply, next_state}
    else
      send(self(), :process_next)
      {:noreply, %{next_state | processing?: true}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    case :queue.out(state.queue) do
      {{:value, {sequence, from, attrs}}, remaining} ->
        result = create_and_broadcast_log(sequence, attrs)
        GenServer.reply(from, result)

        send(self(), :process_next)
        {:noreply, %{state | queue: remaining, processing?: true}}

      {:empty, _queue} ->
        {:noreply, %{state | processing?: false}}
    end
  end

  defp create_and_broadcast_log(sequence, attrs) do
    case LogApp.Logs.create_log(attrs) do
      {:ok, log} ->
        Logger.info(
          "queue_seq=#{sequence} persisted log id=#{log.id} level=#{log.level} workflow_id=#{log.workflow_id}"
        )

        LogApp.Logs.broadcast_log(log)
        {:ok, log}

      {:error, changeset} ->
        Logger.error("queue_seq=#{sequence} failed to persist log: #{inspect(changeset.errors)}")

        {:error, {:validation_failed, changeset}}
    end
  end
end
