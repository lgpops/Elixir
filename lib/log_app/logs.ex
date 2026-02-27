defmodule LogApp.Logs do
  import Ecto.Query, warn: false
  alias LogApp.Repo
  alias LogApp.Log

  def list_logs do
    Repo.all(from l in Log, order_by: [desc: l.inserted_at], limit: 1000)
  end

  def list_logs_for_workflow(workflow_id) do
    Repo.all(
      from l in Log,
        where: l.workflow_id == ^workflow_id,
        order_by: [desc: l.inserted_at]
    )
  end

  def get_log!(id) do
    Repo.get!(Log, id)
  end

  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  def count_logs_by_level do
    from(l in Log,
      group_by: l.level,
      select: {l.level, count(l.id)}
    )
    |> Repo.all()
    |> Map.new()
    |> then(fn counts ->
      %{
        "error" => Map.get(counts, "error", 0),
        "warning" => Map.get(counts, "warning", 0),
        "info" => Map.get(counts, "info", 0),
        "debug" => Map.get(counts, "debug", 0)
      }
    end)
  end

  def list_workflow_ids do
    from(l in Log,
      select: l.workflow_id,
      group_by: l.workflow_id,
      order_by: [desc: max(l.inserted_at)],
      limit: 100
    )
    |> Repo.all()
  end

  def broadcast_log(log) do
    LogAppWeb.Endpoint.broadcast!("logs:updates", "log_created", %{
      id: log.id,
      level: log.level,
      workflow_id: log.workflow_id,
      message: log.message,
      inserted_at: log.inserted_at
    })
  end
end

