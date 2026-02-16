defmodule Aac.Repo do
  use Ecto.Repo,
    otp_app: :aac,
    adapter: Ecto.Adapters.SQLite3
end
