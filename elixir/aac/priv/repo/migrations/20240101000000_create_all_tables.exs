defmodule Aac.Repo.Migrations.CreateAllTables do
  use Ecto.Migration

  def change do
    # Users (people register)
    create table(:users, primary_key: false) do
      add :id, :string, primary_key: true
      add :secret, :string, null: false
      add :failures, :integer, default: 0
      add :psw_changed_at, :integer, null: false
      add :last_auth_success, :integer
      add :last_error, :integer
      add :expire_at, :integer
      add :readable_name, :string, default: ""
      add :session_max, :integer
      add :created_by, :string
      add :created_at, :integer
    end

    # User change history
    create table(:user_changes) do
      add :user_id, references(:users, type: :string, column: :id, on_delete: :delete_all), null: false
      add :changed_by, :string, null: false
      add :changed_at, :integer, null: false
    end

    create index(:user_changes, [:user_id])

    # Branches (organizational hierarchy)
    create table(:branches, primary_key: false) do
      add :id, :string, primary_key: true
      add :parent_id, references(:branches, type: :string, column: :id, on_delete: :nilify_all)
      add :propagate_parent, :boolean, default: false
    end

    create index(:branches, [:parent_id])

    # Branch funcset whitelist
    create table(:branch_whitelists) do
      add :branch_id, references(:branches, type: :string, column: :id, on_delete: :delete_all), null: false
      add :funcset_id, :string, null: false
    end

    create index(:branch_whitelists, [:branch_id])
    create unique_index(:branch_whitelists, [:branch_id, :funcset_id])

    # Function sets
    create table(:funcsets, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, default: ""
      add :branch_id, references(:branches, type: :string, column: :id, on_delete: :delete_all), null: false
    end

    create index(:funcsets, [:branch_id])

    # Functions within function sets
    create table(:funcset_functions) do
      add :funcset_id, references(:funcsets, type: :string, column: :id, on_delete: :delete_all), null: false
      add :function_id, :string, null: false
    end

    create index(:funcset_functions, [:funcset_id])
    create unique_index(:funcset_functions, [:funcset_id, :function_id])

    # Roles
    create table(:roles) do
      add :name, :string, null: false
      add :branch_id, references(:branches, type: :string, column: :id, on_delete: :delete_all), null: false
    end

    create index(:roles, [:branch_id])
    create unique_index(:roles, [:name, :branch_id])

    # Funcsets assigned to roles
    create table(:role_funcsets) do
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      add :funcset_id, :string, null: false
    end

    create index(:role_funcsets, [:role_id])
    create unique_index(:role_funcsets, [:role_id, :funcset_id])

    # Employees (positions in branches)
    create table(:employees) do
      add :branch_id, references(:branches, type: :string, column: :id, on_delete: :delete_all), null: false
      add :position, :string, null: false
      add :person_id, references(:users, type: :string, column: :id, on_delete: :nilify_all)
      add :is_head, :boolean, default: false
    end

    create index(:employees, [:branch_id])
    create index(:employees, [:person_id])

    # Agents
    create table(:agents, primary_key: false) do
      add :agent_id, :string, primary_key: true
      add :branch_id, :string, null: false
      add :description, :string, default: ""
      add :location, :string, default: ""
      add :extra_xml, :string, default: ""
    end

    # Agent tags
    create table(:agent_tags) do
      add :agent_id, references(:agents, type: :string, column: :agent_id, on_delete: :delete_all), null: false
      add :tag, :string, null: false
    end

    create index(:agent_tags, [:agent_id])

    # Function definitions (catalogue)
    create table(:function_defs, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, default: ""
      add :title, :string, default: ""
      add :description, :string, default: ""
      add :tags, :string, default: ""
      add :call_method, :string, default: ""
      add :call_url, :string, default: ""
      add :call_content_type, :string, default: ""
      add :xml_definition, :text, default: ""
    end
  end
end
