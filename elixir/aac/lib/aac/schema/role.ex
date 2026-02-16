defmodule Aac.Schema.Role do
  @moduledoc """
  Role defined in a branch.
  Corresponds to <role> elements under <roles>.
  Role names can repeat across branches (local definitions override parent).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "roles" do
    field :name, :string
    field :branch_id, :string

    has_many :role_funcsets, Aac.Schema.RoleFuncset, foreign_key: :role_id
    belongs_to :branch, Aac.Schema.Branch, foreign_key: :branch_id, references: :id, define_field: false
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :branch_id])
    |> validate_required([:name, :branch_id])
    |> unique_constraint([:name, :branch_id])
  end
end
