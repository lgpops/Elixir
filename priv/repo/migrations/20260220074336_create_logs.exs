defmodule LogApp.Repo.Migrations.CreateLogs do
  use Ecto.Migration

  def change do
    create table(:logs) do
      add :level, :string, null: false
      add :job_id, :uuid, null: false
      add :detail, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:logs, [:job_id])
  end
end
