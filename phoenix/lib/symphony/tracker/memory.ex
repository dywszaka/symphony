defmodule Symphony.Tracker.Memory do
  @moduledoc """
  In-memory tracker adapter for tests and local Phase 1 validation.
  """

  @behaviour Symphony.Tracker.Behaviour

  alias Symphony.Tracker.Issue

  @app :symphony
  @key :memory_tracker_issues

  @spec put_issues([Issue.t() | map()]) :: :ok
  def put_issues(issues) when is_list(issues) do
    Application.put_env(@app, @key, Enum.map(issues, &Issue.normalize/1))
    :ok
  end

  @impl true
  def fetch_candidate_issues, do: {:ok, issues()}

  @impl true
  def fetch_issues_by_states(states) when is_list(states) do
    wanted = MapSet.new(Enum.map(states, &normalize_state/1))
    {:ok, Enum.filter(issues(), &(normalize_state(&1.state) in wanted))}
  end

  @impl true
  def fetch_issue_states_by_ids(ids) when is_list(ids) do
    wanted = MapSet.new(ids)
    {:ok, Enum.filter(issues(), &(&1.id in wanted))}
  end

  defp issues, do: Application.get_env(@app, @key, [])
  defp normalize_state(state), do: state |> to_string() |> String.downcase()
end
