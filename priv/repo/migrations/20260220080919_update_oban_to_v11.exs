defmodule LogApp.Repo.Migrations.UpdateObanToV11 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 11)
  end

  def down do
    Oban.Migration.down(version: 10)
  end
end
