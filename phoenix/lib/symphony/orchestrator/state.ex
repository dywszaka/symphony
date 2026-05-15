defmodule Symphony.Orchestrator.State do
  @moduledoc """
  Runtime state owned by the orchestrator.
  """

  defstruct poll_interval_ms: 30_000,
            max_concurrent_agents: 10,
            tracker: Symphony.Tracker.Memory,
            runner: nil,
            runner_opts: [],
            settings: nil,
            auto_poll: false,
            poll_timer_ref: nil,
            continuation_retry_delay_ms: 1_000,
            failure_retry_base_ms: 10_000,
            running: %{},
            claimed: MapSet.new(),
            retry_attempts: %{},
            completed: MapSet.new(),
            codex_totals: %{
              input_tokens: 0,
              output_tokens: 0,
              total_tokens: 0,
              seconds_running: 0
            },
            codex_rate_limits: nil

  @type t :: %__MODULE__{}

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      poll_interval_ms: state.poll_interval_ms,
      max_concurrent_agents: state.max_concurrent_agents,
      running:
        Map.new(state.running, fn {issue_id, entry} ->
          {issue_id, snapshot_running_entry(entry)}
        end),
      claimed: MapSet.to_list(state.claimed),
      retry_attempts:
        Map.new(state.retry_attempts, fn {issue_id, entry} ->
          {issue_id, snapshot_retry_entry(entry)}
        end),
      completed: MapSet.to_list(state.completed),
      codex_totals: live_codex_totals(state),
      codex_rate_limits: state.codex_rate_limits
    }
  end

  defp snapshot_running_entry(entry) do
    %{
      issue_id: entry.issue.id,
      identifier: entry.identifier,
      title: entry.issue.title,
      state: entry.state,
      started_at_ms: entry.started_at_ms,
      attempt: entry.attempt,
      session_id: Map.get(entry, :session_id),
      last_codex_event: Map.get(entry, :last_codex_event),
      last_codex_timestamp_ms: Map.get(entry, :last_codex_timestamp_ms),
      codex_input_tokens: Map.get(entry, :codex_input_tokens, 0),
      codex_output_tokens: Map.get(entry, :codex_output_tokens, 0),
      codex_total_tokens: Map.get(entry, :codex_total_tokens, 0)
    }
  end

  defp snapshot_retry_entry(entry) do
    %{
      issue_id: entry.issue_id,
      identifier: entry.identifier,
      attempt: entry.attempt,
      due_at_ms: entry.due_at_ms,
      error: entry.error
    }
  end

  defp live_codex_totals(state) do
    active_seconds =
      state.running
      |> Map.values()
      |> Enum.reduce(0, fn entry, acc ->
        acc + max(div(System.monotonic_time(:millisecond) - entry.started_at_ms, 1_000), 0)
      end)

    Map.update!(state.codex_totals, :seconds_running, &(&1 + active_seconds))
  end
end
