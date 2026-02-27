defmodule LogApp.Log do
  use Ecto.Schema
  import Ecto.Changeset

  schema "logs" do
    field :level, :string
    field :workflow_id, Ecto.UUID
    field :message, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:level, :workflow_id, :message])
    |> validate_required([:level, :workflow_id, :message])
    |> validate_inclusion(:level, ["debug", "info", "warning", "error"])
  end
end
