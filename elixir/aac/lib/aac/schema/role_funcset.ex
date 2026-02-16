defmodule Aac.Schema.RoleFuncset do
  @moduledoc """
  Funcset assigned to a role.
  Corresponds to <funcset> elements inside <role>.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "role_funcsets" do
    field :role_id, :integer
    field :funcset_id, :string
  end

  def changeset(rf, attrs) do
    rf
    |> cast(attrs, [:role_id, :funcset_id])
    |> validate_required([:role_id, :funcset_id])
    |> unique_constraint([:role_id, :funcset_id])
  end
end
