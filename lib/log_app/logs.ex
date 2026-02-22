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

