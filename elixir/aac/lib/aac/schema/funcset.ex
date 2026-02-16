defmodule Aac.Schema.Funcset do
  @moduledoc """
  Function set - a named collection of functions.
  Corresponds to <funcset> elements under <deffuncsets>.
  Funcset IDs are globally unique.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "funcsets" do
    field :name, :string, default: ""
    field :branch_id, :string

    has_many :functions, Aac.Schema.FuncsetFunction, foreign_key: :funcset_id
    belongs_to :branch, Aac.Schema.Branch, foreign_key: :branch_id, references: :id, define_field: false
  end

  def changeset(funcset, attrs) do
    funcset
    |> cast(attrs, [:id, :name, :branch_id])
    |> validate_required([:id, :branch_id])
    |> unique_constraint(:id, name: :funcsets_pkey)
  end
end
