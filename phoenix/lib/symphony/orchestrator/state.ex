defmodule Symphony.Orchestrator.State do
  @moduledoc """
  Runtime state owned by the orchestrator.
  """

  defstruct poll_interval_ms: 30_000,
            max_concurrent_agents: 10,
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
      running: state.running,
      claimed: MapSet.to_list(state.claimed),
      retry_attempts: state.retry_attempts,
      completed: MapSet.to_list(state.completed),
      codex_totals: state.codex_totals,
      codex_rate_limits: state.codex_rate_limits
    }
  end
end
