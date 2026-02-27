defmodule LogApp.Repo.Migrations.RebuildLogsForIngress do
  use Ecto.Migration

  def up do
    # Drop old logs table
    drop_if_exists(table(:logs))

    # Create new simplified logs table
    create table(:logs) do
      add :level, :string, null: false
      add :workflow_id, :uuid, null: false
      add :message, :jsonb, null: false
      timestamps(type: :utc_datetime)
    end

    # Create index on workflow_id for fast filtering
    create index(:logs, [:workflow_id])
  end

  def down do
    drop_if_exists(table(:logs))
  end
end
