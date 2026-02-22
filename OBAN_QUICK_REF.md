# Oban Quick Reference Guide for LogApp

## Core Concepts

**Oban = Reliable Job Queue**
- Jobs are enqueued to a database-backed queue
- Workers process jobs with automatic retries
- Job state is tracked (available → executing → completed/discarded)
- Multiple queues, configurable concurrency

## Typical Usage Patterns

### Basic Logging
```elixir
LogApp.TemporalHelper.log_info(job_id, %{"event" => "started"})
# Enqueues immediately, processes ASAP
# Returns: {:ok, %Oban.Job{}} or {:error, reason}
```

### Delayed Logging (Batching)
```elixir
LogApp.TemporalHelper.log_workflow_delayed(
  job_id, 
  "info", 
  %{"event" => "step_1"}, 
  30  # Wait 30 seconds
)
# Useful for rate limiting or batching requests
```

### Scheduled Logging
```elixir
LogApp.TemporalHelper.log_workflow_at(
  job_id,
  "info",
  %{"event" => "completion_check"},
  ~U[2026-02-20 10:00:00Z]
)
# Execute at a specific time
```

### Batch Logging
```elixir
logs = [
  %{job_id: id1, level: "info", detail: %{...}},
  %{job_id: id2, level: "error", detail: %{...}}
]
LogApp.TemporalHelper.log_batch(logs)
# Single transaction for multiple jobs
```

### Job Monitoring
```elixir
LogApp.TemporalHelper.job_status(workflow_id)
# Returns: [%{state: :executing, attempt: 1, ...}]
```

## Worker Return Values (Control Flow)

In `LogApp.LogWorker.perform/1`:

```elixir
def perform(job) do
  case do_work(job) do
    # ✅ Success - Job complete
    {:ok, data} -> :ok
    
    # ❌ Validation failed - Don't retry
    {:error, :validation} -> {:cancel, :validation}
    
    # ⚠️  Database error - Retry after delay
    {:error, :database} -> {:snooze, 5}
    
    # ⚠️  Rate limited - Retry later
    {:error, :rate_limit} -> {:reschedule, 30}
    
    # ⚠️  Unexpected - Retry with backoff
    {:error, _} -> {:snooze, 10}
  end
end
```

## Queue Configuration

### In config/config.exs:
```elixir
config :log_app, Oban,
  queues: [
    logs: [limit: 50],      # Max 50 concurrent log jobs
    default: [limit: 10],   # Max 10 concurrent other jobs
    critical: [limit: 1]    # Sequential processing
  ]
```

### In worker definition:
```elixir
use Oban.Worker,
  queue: :logs,             # Which queue to use
  max_attempts: 3,          # Retry up to 3 times
  unique: [                 # Prevent duplicates
    period: 60,             # Within 60 seconds
    fields: [:args]         # Based on job arguments
  ]
```

## Testing

### In config/test.exs:
```elixir
config :log_app, Oban, testing: :manual
```

### In test file:
```elixir
test "logs are created" do
  # Insert job manually
  {:ok, job} = LogApp.LogWorker.new(%{...}) |> Oban.insert()
  
  # Execute it
  assert :ok = LogApp.LogWorker.perform(job)
  
  # Verify side effects
  assert log = LogApp.Repo.get(LogApp.Log, ...)
end
```

## Monitoring Queries

```elixir
# All jobs for a workflow
from(j in Oban.Job,
  where: j.args["job_id"] == ^workflow_id
)

# Failed jobs (last day)
from(j in Oban.Job,
  where: j.state in [:discarded] and
         j.attempted_at > ago(1, :day)
)

# Jobs by state
Oban.Job
|> where([j], j.state in [:available, :executing])
|> select([j], {j.state, count(j.id)})
|> group_by([j], j.state)
```

## Troubleshooting

### Job Not Processing?
```bash
# Check Oban is running
mix phx.server

# Check job in database
psql log_app_dev -c "SELECT id, state, queue FROM oban_jobs;"

# Check logs
# Look for [error] messages in server output
```

### Duplicate Logs?
Add unique constraint:
```elixir
use Oban.Worker,
  unique: [period: 60, fields: [:args]]
```

### Job Keeps Failing?
```elixir
# Return {:cancel, reason} for non-retriable errors
# Return {:snooze, seconds} for retriable errors

# Check database logs:
psql log_app_dev -c "SELECT errors FROM oban_jobs WHERE id = $1;"
```

### Too Slow?
Check concurrency:
```elixir
# Increase limit in config
queues: [logs: [limit: 100]]

# Or use multiple nodes/machines
# Each runs its own queue workers
```

## Common Gotchas

### ❌ Using Oban.insert!()
```elixir
# Bad - ignores errors
LogWorker.new(...) |> Oban.insert!()

# Good - handle result
case LogWorker.new(...) |> Oban.insert() do
  {:ok, job} -> {:ok, job}
  {:error, reason} -> {:error, reason}
end
```

### ❌ Returning {:error} for All Failures
```elixir
# Bad - retries forever (up to max_attempts)
case do_work() do
  :ok -> :ok
  error -> error  # ❌ Retries validation errors too
end

# Good - distinguish errors
case do_work() do
  :ok -> :ok
  {:error, :validation} -> {:cancel, :validation}  # ✅ Don't retry
  {:error, :db} -> {:snooze, 5}                   # ✅ Retry with delay
end
```

### ❌ Missing Unique Configuration
```elixir
# Bad - duplicates possible
use Oban.Worker, queue: :logs

# Good - deduped
use Oban.Worker,
  queue: :logs,
  unique: [period: 60, fields: [:args]]
```

## Performance Tips

1. **Use batch operations**
   ```elixir
   Oban.insert_all(jobs)  # Single transaction
   ```

2. **Set appropriate concurrency**
   ```elixir
   queues: [logs: [limit: 50]]  # Depends on DB connections
   ```

3. **Add unique constraints**
   - Prevents duplicate processing
   - Reduces database load

4. **Use proper error handling**
   - Cancel bad data immediately
   - Retry database errors with backoff

5. **Monitor job duration**
   - Track slow jobs
   - Identify bottlenecks

## Resources

- [Oban Documentation](https://hexdocs.pm/oban)
- [Oban GitHub](https://github.com/sorentwo/oban)
- [Job Queue Best Practices](https://wiki.postgresql.org/wiki/Number_Of_Database_Connections)

## Common Job Return Patterns

```elixir
# Pattern 1: Simple Success/Retry
def perform(job) do
  case do_work(job) do
    :ok -> :ok
    :error -> {:snooze, 5}
  end
end

# Pattern 2: Detailed Error Handling
def perform(job) do
  with {:ok, data} <- validate(job.args),
       {:ok, result} <- process(data),
       :ok <- persist(result) do
    :ok
  else
    {:error, :validation} -> {:cancel, :validation}
    {:error, :not_found} -> {:cancel, :not_found}
    {:error, _} -> {:snooze, 5}
  end
end

# Pattern 3: With Telemetry
def perform(job) do
  :telemetry.span(:log_worker, %{job_id: job.id}, fn ->
    result = do_work(job)
    {result, %{success: result == :ok}}
  end)
end
```

## When to Use Different Log Levels in Temporal

```elixir
# Workflow started
LogApp.TemporalHelper.log_info(workflow_id, %{"event" => "started"})

# Step completed
LogApp.TemporalHelper.log_info(workflow_id, %{"step" => "processing", "duration_ms" => 234})

# Retryable failure
LogApp.TemporalHelper.log_warning(workflow_id, %{"error" => "timeout", "will_retry" => true})

# Unrecoverable failure
LogApp.TemporalHelper.log_error(workflow_id, %{"error" => "invalid data", "final" => true})

# Debug info (if enabled)
LogApp.TemporalHelper.log_debug(workflow_id, %{"internal" => "state", "details" => "..."})
```
