defmodule AacWeb.ResponseHelper do
  @moduledoc """
  Maps AAC reason codes to HTTP status codes.
  Port of Python's add_respcode_by_reason function.
  """

  @reason_to_status %{
    "WRONG-FORMAT" => 400,
    "WRONG-DATA" => 400,
    "USER-UNKNOWN" => 401,
    "WRONG-SECRET" => 403,
    "SECRET-EXPIRED" => 403,
    "ALREADY-EXISTS" => 403,
    "USER-EMPLOYED" => 403,
    "ALREADY-UNEMPLOYED" => 403,
    "FUNCTION-UNKNOWN" => 404,
    "FUNCSET-UNKNOWN" => 404,
    "ROLE-UNKNOWN" => 404,
    "PROP-UNKNOWN" => 404,
    "BRANCH-UNKNOWN" => 404,
    "AGENT-UNKNOWN" => 404,
    "NOT-IN-SET" => 404,
    "NOT-ALLOWED" => 405,
    "DATABASE-ERROR" => 500,
    "OP-UNAUTHORIZED" => 401,
    "OPERATOR-UNKNOWN" => 401,
    "FORBIDDEN-FOR-OP" => 403
  }

  def status_for(%{"reason" => reason}) do
    Map.get(@reason_to_status, reason, 200)
  end
  def status_for(_), do: 200
end
