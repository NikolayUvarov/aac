defmodule Aac.Schema.Agent do
  @moduledoc """
  A registered agent (device/service) assigned to a branch.
  Corresponds to Agents table in agents.db.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:agent_id, :string, autogenerate: false}

  schema "agents" do
    field :branch_id, :string
    field :description, :string, default: ""
    field :location, :string, default: ""
    field :extra_xml, :string, default: ""

    has_many :tags, Aac.Schema.AgentTag, foreign_key: :agent_id
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:agent_id, :branch_id, :description, :location, :extra_xml])
    |> validate_required([:agent_id, :branch_id])
  end
end
