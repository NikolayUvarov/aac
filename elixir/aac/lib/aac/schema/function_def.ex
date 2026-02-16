defmodule Aac.Schema.FunctionDef do
  @moduledoc """
  Function definition from the catalogue.
  Corresponds to <function> elements in catalogues.xml.
  The full XML definition is stored in xml_definition for compatibility.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "function_defs" do
    field :name, :string, default: ""
    field :title, :string, default: ""
    field :description, :string, default: ""
    field :tags, :string, default: ""
    field :call_method, :string, default: ""
    field :call_url, :string, default: ""
    field :call_content_type, :string, default: ""
    field :xml_definition, :string, default: ""
  end

  def changeset(func, attrs) do
    func
    |> cast(attrs, [:id, :name, :title, :description, :tags, :call_method, :call_url, :call_content_type, :xml_definition])
    |> validate_required([:id])
  end
end
