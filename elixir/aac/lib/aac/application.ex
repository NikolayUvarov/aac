defmodule Aac.Application do
  @moduledoc """
  AAC (Authenticate, Authorize, Configure) - OTP Application.

  Hierarchical RBAC system with:
  - Organizational branches (nested hierarchy)
  - Roles, function sets, whitelists
  - User, employee, and agent management
  - Function catalogue with parametric definitions
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Aac.Repo,
      {Phoenix.PubSub, name: Aac.PubSub},
      Aac.TestRunner,
      AacWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Aac.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AacWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
