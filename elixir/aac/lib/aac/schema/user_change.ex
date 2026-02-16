defmodule Aac.Schema.UserChange do
  @moduledoc """
  Tracks changes to user records.
  Corresponds to <changed> elements under <person>.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_changes" do
    field :user_id, :string
    field :changed_by, :string
    field :changed_at, :integer
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [:user_id, :changed_by, :changed_at])
    |> validate_required([:user_id, :changed_by, :changed_at])
  end
end
