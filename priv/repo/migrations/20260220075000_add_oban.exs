defmodule LogApp.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban was removed from the project. This migration is now a no-op.
  # The rebuild_logs_for_ingress migration handles cleanup of any Oban artifacts.
  def up, do: :ok
  def down, do: :ok
end
