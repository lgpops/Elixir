defmodule LogApp.Repo do
  use Ecto.Repo,
    otp_app: :log_app,
    adapter: Ecto.Adapters.Postgres
end
