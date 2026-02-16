defmodule Aac.Schema.User do
  @moduledoc """
  User (person) in the people register.
  Corresponds to <person> elements in universe.xml.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "users" do
    field :secret, :string
    field :failures, :integer, default: 0
    field :psw_changed_at, :integer
    field :last_auth_success, :integer
    field :last_error, :integer
    field :expire_at, :integer
    field :readable_name, :string, default: ""
    field :session_max, :integer
    field :created_by, :string
    field :created_at, :integer

    has_many :changes, Aac.Schema.UserChange, foreign_key: :user_id
    has_many :employments, Aac.Schema.Employee, foreign_key: :person_id
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :id, :secret, :failures, :psw_changed_at, :last_auth_success,
      :last_error, :expire_at, :readable_name, :session_max,
      :created_by, :created_at
    ])
    |> validate_required([:id, :secret, :psw_changed_at])
  end
end
