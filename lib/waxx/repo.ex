defmodule Waxx.Repo do
  use Ecto.Repo,
    otp_app: :waxx,
    adapter: Ecto.Adapters.Postgres
end
