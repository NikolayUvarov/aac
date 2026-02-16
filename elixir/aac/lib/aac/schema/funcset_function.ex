defmodule Aac.Schema.FuncsetFunction do
  @moduledoc """
  A function belonging to a funcset.
  Corresponds to <func> elements inside <funcset>.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "funcset_functions" do
    field :funcset_id, :string
    field :function_id, :string
  end

  def changeset(ff, attrs) do
    ff
    |> cast(attrs, [:funcset_id, :function_id])
    |> validate_required([:funcset_id, :function_id])
    |> unique_constraint([:funcset_id, :function_id])
  end
end
