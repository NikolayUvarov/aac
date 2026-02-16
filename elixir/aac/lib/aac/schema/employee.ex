defmodule Aac.Schema.Employee do
  @moduledoc """
  An employee position in a branch.
  Corresponds to <employee> elements under <employees>.
  When person_id is nil, the position is vacant.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    field :branch_id, :string
    field :position, :string
    field :person_id, :string
    field :is_head, :boolean, default: false

    belongs_to :branch, Aac.Schema.Branch, foreign_key: :branch_id, references: :id, define_field: false
    belongs_to :person, Aac.Schema.User, foreign_key: :person_id, references: :id, define_field: false
  end

  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [:branch_id, :position, :person_id, :is_head])
    |> validate_required([:branch_id, :position])
  end
end
