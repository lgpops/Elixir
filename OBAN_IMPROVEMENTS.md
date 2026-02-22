# Oban Job Queue - Design & Improvements Guide

## What Changed and Why

### The Problem with Your Original Design

Your original implementation treated Oban like a message broker:
```elixir
LogWorker.new(%{...}) |> Oban.insert!()  # Fire and forget
```

This ignored Oban's core strengths:
- **No retry logic**: Failed logs were lost
- **No validation**: Invalid data would fail silent
- **No scheduling**: All jobs ran immediately
- **No deduplication**: Duplicate logs possible
- **No monitoring**: Couldn't track job status
- **Single queue**: No prioritization

### The Improvement: Treating Oban as a Job Queue

Oban is designed to be:
- **Reliable**: Transactional guarantees, durable in database
- **Resilient**: Smart retry strategies with exponential backoff
- **Trackable**: Full job state and history
- **Schedulable**: Delay execution, schedule for future
- **Observable**: Job monitoring and telemetry

## New Features Explained

### 1. Unique Constraints (Prevent Duplicates)

```elixir
use Oban.Worker,
  queue: :logs,
  unique: [period: 60, fields: [:args]]
```

**What it does:**
- Prevents the same log from being processed twice within 60 seconds
- Uses job arguments as the unique key
- Silently deduplicates (returns `:ok` if duplicate detected)

**Use case:** If Temporal accidentally enqueues the same log twice, Oban handles it gracefully.

### 2. Max Attempts & Retry Strategy

```elixir
use Oban.Worker,
  max_attempts: 3
```

**What it does:**
- Automatically retries failed jobs up to 3 times
- Uses exponential backoff: 1s, 10s, 100s delays
- Tracks each attempt

**Return values in perform/1:**
- `:ok` → Job succeeded, mark complete
- `{:error, reason}` → Job failed, max retries used, mark discarded
- `{:cancel, reason}` → Job invalid, don't retry
- `{:snooze, seconds}` → Retry again in N seconds
- `{:reschedule, seconds}` → Reschedule for future time

### 3. Separate Queues with Concurrency Limits

```elixir
queues: [
  logs: [limit: 50],    # High throughput queue
  default: [limit: 10]  # Standard background jobs
]
```

**What it does:**
- `limit: 50` means max 50 concurrent log jobs
- Isolates log processing from other background jobs
- Prevents log processing from starving other work

**Why this matters:** If you add email workers, batch processors, etc., logs won't block them.

### 4. Better Error Handling

Old code:
```elixir
case create_log_from_args(args) do
  {:ok, log} -> :ok
  {:error, reason} -> {:error, reason}  # Will retry all errors
end
```

New code:
```elixir
with {:ok, log_attrs} <- validate_log_args(args),
     {:ok, log} <- Logs.create_log(log_attrs) do
  Logs.create_log_notification(log)
  {:ok, log}
end
```

**The difference:**
- Validates data BEFORE database operations
- Returns `{:cancel, :validation}` for bad data (no retries)
- Returns `{:snooze, 5}` for database errors (retry after 5s)
- Distinguishes between retriable and non-retriable errors

### 5. Job Options (Scheduling)

```elixir
# Execute immediately
log_workflow(job_id, "info", data)

# Execute in 30 seconds (batching)
log_workflow_delayed(job_id, "info", data, 30)

# Execute at specific time
log_workflow_at(job_id, "info", data, ~U[2026-02-20 10:00:00Z])
```

**Use cases:**
- **Rate limiting**: Delay high-volume log processing
- **Batching**: Accumulate logs before processing
- **Time-based**: Log at specific workflow milestones
- **Retry strategy**: Add delays between retries

### 6. Batch Insertion

```elixir
logs = [
  %{job_id: id1, level: "info", detail: %{...}},
  %{job_id: id2, level: "error", detail: %{...}}
]
log_batch(logs)
```

**Advantage:** Single database transaction for multiple jobs instead of individual inserts.

### 7. Job Monitoring

```elixir
job_status(job_id)
```

Returns:
```elixir
[
  %{
    state: :executing,        # :available, :executing, :completed, :discarded
    attempt: 1,
    max_attempts: 3,
    error: nil,               # Last error message if any
    scheduled_at: ~U[...],
    attempted_at: ~U[...]
  }
]
```

**Use case:** Query job status from a dashboard or webhook endpoint.

## Oban vs Message Queues: When to Use What

### Use Oban Job Queue For:
- **Logging** ✅ (Your use case)
- Email sending
- Data processing
- Report generation  
- Image resizing
- Any background work that needs:
  - Retry on failure
  - Durable execution guarantee
  - Job tracking
  - Schedulable execution

### Use Message Queue (RabbitMQ, Kafka) For:
- High-frequency streaming data (1000s/sec)
- Pub/Sub patterns (multiple subscribers)
- Complex routing logic
- Long-lived message retention
- Distributed systems coordination

## Elixir-Specific Best Practices

### 1. Use Pattern Matching in Returns

```elixir
# Instead of if-else:
case validate_args(args) do
  {:ok, data} -> {:ok, data}
  {:error, :invalid_level} -> {:cancel, :invalid_level}
  {:error, :invalid_job_id} -> {:cancel, :invalid_job_id}
  {:error, :db_connection} -> {:snooze, 5}
end
```

### 2. Leverage `with` for Error Handling

```elixir
with {:ok, log_attrs} <- validate_log_args(args),
     {:ok, log} <- Logs.create_log(log_attrs),
     :ok <- broadcast_log(log) do
  :ok
else
  {:error, :validation} -> {:cancel, :invalid_data}
  {:error, _} -> {:snooze, 5}
end
```

### 3. Use Telemetry for Observability

```elixir
def perform(job) do
  :telemetry.span(:log_worker, %{queue: "logs"}, fn ->
    case do_work(job) do
      :ok -> {:ok, %{status: :success}}
      error -> {error, %{status: :failed}}
    end
  end)
end
```

### 4. Compose Workers with Pipes

```elixir
def process_workflow(workflow_id) do
  workflow_id
  |> fetch_workflow()
  |> then(&log_start(&1))
  |> execute_steps()
  |> then(&log_completion(&1))
end
```

## Testing Strategies

### Test Configuration (config/test.exs)
```elixir
config :log_app, Oban, testing: :manual
```

This prevents auto-execution so you can test:

```elixir
defmodule LogApp.LogWorkerTest do
  use ExUnit.Case
  
  test "creates log entry" do
    {:ok, job} = LogApp.LogWorker.new(%{...}) |> Oban.insert()
    
    # Manually execute the job
    assert :ok = LogApp.LogWorker.perform(job)
    
    # Verify log was created
    assert log = LogApp.Repo.get(LogApp.Log, ...)
  end
  
  test "retries on database error" do
    # Mock database to fail
    job = %Oban.Job{...}
    assert {:snooze, 5} = LogApp.LogWorker.perform(job)
  end
end
```

## Production Checklist

- [ ] Set appropriate `max_attempts` based on error tolerance
- [ ] Configure separate queues for different job types
- [ ] Add telemetry/monitoring for job failures
- [ ] Set up log rotation for job error history
- [ ] Test job behavior under database stress
- [ ] Add unique constraints for idempotent operations
- [ ] Implement metrics (job count, success rate, duration)
- [ ] Document retry behavior in code comments
- [ ] Test graceful shutdown (15s grace period)

## Example: Real-World Usage

```elixir
# In your Temporal workflow callback:
defmodule MyTemporalCallback do
  def on_step_complete(workflow_id, step_name, duration_ms) do
    LogApp.TemporalHelper.log_info(workflow_id, %{
      "event" => "step_completed",
      "step" => step_name,
      "duration_ms" => duration_ms
    })
  end
  
  def on_step_error(workflow_id, step_name, error) do
    LogApp.TemporalHelper.log_error(workflow_id, %{
      "event" => "step_failed",
      "step" => step_name,
      "error_message" => error.message,
      "retry_count" => error.retry_count
    })
  end
end
```

The log jobs will:
1. ✅ Be deduped if sent twice
2. ✅ Retry automatically if database is busy
3. ✅ Be tracked for monitoring
4. ✅ Be processable at high concurrency (50 concurrent)
5. ✅ Validate data before processing
