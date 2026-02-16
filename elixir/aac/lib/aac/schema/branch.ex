defmodule Aac.Schema.Branch do
  @moduledoc """
  Organizational branch in the hierarchy.
  Corresponds to <branch> elements in universe.xml.
  Supports unlimited nesting via parent_id.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "branches" do
    field :parent_id, :string
    field :propagate_parent, :boolean, default: false

    has_many :children, __MODULE__, foreign_key: :parent_id, references: :id
    has_many :employees, Aac.Schema.Employee, foreign_key: :branch_id
    has_many :roles, Aac.Schema.Role, foreign_key: :branch_id
    has_many :funcsets, Aac.Schema.Funcset, foreign_key: :branch_id
    has_many :whitelist_entries, Aac.Schema.BranchWhitelist, foreign_key: :branch_id
    belongs_to :parent, __MODULE__, foreign_key: :parent_id, references: :id, define_field: false
  end

  def changeset(branch, attrs) do
    branch
    |> cast(attrs, [:id, :parent_id, :propagate_parent])
    |> validate_required([:id])
  end
end
