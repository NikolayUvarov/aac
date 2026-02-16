defmodule Aac.Schema.BranchWhitelist do
  @moduledoc """
  Funcset whitelist entry for a branch.
  Corresponds to <funcset> elements under <func_white_list>.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "branch_whitelists" do
    field :branch_id, :string
    field :funcset_id, :string
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:branch_id, :funcset_id])
    |> validate_required([:branch_id, :funcset_id])
  end
end
