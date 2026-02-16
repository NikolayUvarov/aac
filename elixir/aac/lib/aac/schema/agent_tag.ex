defmodule Aac.Schema.AgentTag do
  @moduledoc """
  Tag associated with an agent.
  Corresponds to Tags table in agents.db.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_tags" do
    field :agent_id, :string
    field :tag, :string
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:agent_id, :tag])
    |> validate_required([:agent_id, :tag])
  end
end
