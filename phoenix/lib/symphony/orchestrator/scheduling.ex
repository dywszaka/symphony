defmodule Symphony.Orchestrator.Scheduling do
  @moduledoc """
  Pure scheduling rules used by the orchestrator.
  """

  alias Symphony.Tracker.Issue

  @spec sort_issues([Issue.t()]) :: [Issue.t()]
  def sort_issues(issues) when is_list(issues) do
    Enum.sort_by(issues, fn issue ->
      {
        priority_sort_value(issue.priority),
        created_at_sort_value(issue.created_at),
        issue.identifier || ""
      }
    end)
  end

  @spec dispatch_eligible?(Issue.t(), [String.t()], [String.t()], keyword()) :: boolean()
  def dispatch_eligible?(%Issue{} = issue, active_states, terminal_states, opts \\ []) do
    running = Keyword.get(opts, :running, %{})
    claimed = Keyword.get(opts, :claimed, MapSet.new())
    max_concurrent_agents = Keyword.get(opts, :max_concurrent_agents, 10)
    state_limits = Keyword.get(opts, :max_concurrent_agents_by_state, %{})

    core_issue_fields?(issue) and
      active_state?(issue.state, active_states) and
      not terminal_state?(issue.state, terminal_states) and
      not MapSet.member?(claimed, issue.id) and
      not Map.has_key?(running, issue.id) and
      map_size(running) < max_concurrent_agents and
      state_slot_available?(issue.state, running, state_limits, max_concurrent_agents) and
      todo_blockers_clear?(issue, terminal_states)
  end

  @spec active_state?(term(), [String.t()]) :: boolean()
  def active_state?(state, active_states), do: normalized_member?(state, active_states)

  @spec terminal_state?(term(), [String.t()]) :: boolean()
  def terminal_state?(state, terminal_states), do: normalized_member?(state, terminal_states)

  defp core_issue_fields?(%Issue{} = issue) do
    present?(issue.id) and present?(issue.identifier) and present?(issue.title) and
      present?(issue.state)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp normalized_member?(state, states) when is_list(states) do
    normalized_state = normalize_state(state)
    Enum.any?(states, &(normalize_state(&1) == normalized_state))
  end

  defp normalize_state(state) when is_binary(state),
    do: state |> String.trim() |> String.downcase()

  defp normalize_state(state), do: state |> to_string() |> String.trim() |> String.downcase()

  defp todo_blockers_clear?(%Issue{state: state, blocked_by: blockers}, terminal_states) do
    if normalize_state(state) == "todo" do
      Enum.all?(blockers || [], fn blocker ->
        blocker
        |> blocker_state()
        |> terminal_state?(terminal_states)
      end)
    else
      true
    end
  end

  defp blocker_state(%{state: state}), do: state
  defp blocker_state(%{"state" => state}), do: state
  defp blocker_state(_blocker), do: nil

  defp state_slot_available?(state, running, state_limits, global_limit) do
    normalized_state = normalize_state(state)
    limit = Map.get(state_limits, normalized_state, global_limit)

    running
    |> Enum.count(fn {_id, entry} ->
      normalize_state(Map.get(entry, :state) || Map.get(entry, "state")) == normalized_state
    end)
    |> Kernel.<(limit)
  end

  defp priority_sort_value(priority) when is_integer(priority), do: priority
  defp priority_sort_value(_priority), do: 1_000_000

  defp created_at_sort_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  defp created_at_sort_value(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

  defp created_at_sort_value(_value), do: 9_999_999_999_999_999
end
