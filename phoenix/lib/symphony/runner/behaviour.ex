defmodule Symphony.Runner.Behaviour do
  @moduledoc """
  Runner contract used by the orchestrator.
  """

  alias Symphony.Tracker.Issue

  @callback start_issue(Issue.t(), keyword()) :: {:ok, pid()} | {:error, term()}
end
