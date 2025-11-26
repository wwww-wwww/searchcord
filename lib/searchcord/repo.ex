defmodule Searchcord.Repo do
  use Ecto.Repo,
    otp_app: :searchcord,
    adapter: Ecto.Adapters.Postgres
end
