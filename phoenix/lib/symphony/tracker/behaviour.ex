defmodule Symphony.Tracker.Behaviour do
  @moduledoc """
  Tracker read contract required by the orchestrator.
  """

  alias Symphony.Tracker.Issue

  @callback fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
end
