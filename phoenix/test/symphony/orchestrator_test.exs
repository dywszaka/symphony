defmodule Symphony.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator

  test "starts and exposes a spec-shaped snapshot" do
    start_supervised!({Orchestrator, name: :phase1_orchestrator_test})

    assert {:ok, snapshot} = Orchestrator.snapshot(:phase1_orchestrator_test)
    assert snapshot.poll_interval_ms == 30_000
    assert snapshot.max_concurrent_agents == 10
    assert snapshot.running == %{}
    assert snapshot.claimed == []
    assert snapshot.retry_attempts == %{}
    assert snapshot.completed == []

    assert snapshot.codex_totals == %{
             input_tokens: 0,
             output_tokens: 0,
             total_tokens: 0,
             seconds_running: 0
           }

    assert snapshot.codex_rate_limits == nil
  end
end
