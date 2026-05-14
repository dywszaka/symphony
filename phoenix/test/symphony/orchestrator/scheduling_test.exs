defmodule Symphony.Orchestrator.SchedulingTest do
  use ExUnit.Case, async: true

  alias Symphony.Orchestrator.Scheduling
  alias Symphony.Tracker.Issue

  test "sorts by priority, created_at, and identifier" do
    issues = [
      issue("3", "MT-3", priority: nil, created_at: ~U[2026-01-01 00:00:00Z]),
      issue("2", "MT-2", priority: 1, created_at: ~U[2026-01-02 00:00:00Z]),
      issue("1", "MT-1", priority: 1, created_at: ~U[2026-01-01 00:00:00Z]),
      issue("4", "AA-4", priority: 1, created_at: ~U[2026-01-01 00:00:00Z])
    ]

    assert Scheduling.sort_issues(issues) |> Enum.map(& &1.identifier) == [
             "AA-4",
             "MT-1",
             "MT-2",
             "MT-3"
           ]
  end

  test "requires core issue fields and active non-terminal state" do
    active = ["Todo", "In Progress"]
    terminal = ["Done"]

    assert Scheduling.dispatch_eligible?(issue("1", "MT-1", state: "Todo"), active, terminal)

    refute Scheduling.dispatch_eligible?(
             %Issue{id: nil, identifier: "MT-1", title: "Title", state: "Todo"},
             active,
             terminal
           )

    refute Scheduling.dispatch_eligible?(issue("2", "MT-2", state: "Done"), active, terminal)
    refute Scheduling.dispatch_eligible?(issue("3", "MT-3", state: "Review"), active, terminal)
  end

  test "blocks Todo issues when any blocker is non-terminal" do
    active = ["Todo"]
    terminal = ["Done", "Canceled"]

    blocked =
      issue("1", "MT-1",
        state: "Todo",
        blocked_by: [%{id: "b1", identifier: "MT-0", state: "In Progress"}]
      )

    unblocked =
      issue("2", "MT-2",
        state: "Todo",
        blocked_by: [%{id: "b2", identifier: "MT-9", state: "Done"}]
      )

    refute Scheduling.dispatch_eligible?(blocked, active, terminal)
    assert Scheduling.dispatch_eligible?(unblocked, active, terminal)
  end

  test "rejects claimed, running, global full, and per-state full issues" do
    issue = issue("1", "MT-1", state: "Todo")

    refute Scheduling.dispatch_eligible?(issue, ["Todo"], ["Done"],
             claimed: MapSet.new(["1"]),
             running: %{},
             max_concurrent_agents: 10
           )

    refute Scheduling.dispatch_eligible?(issue, ["Todo"], ["Done"],
             claimed: MapSet.new(),
             running: %{"1" => %{state: "Todo"}},
             max_concurrent_agents: 10
           )

    refute Scheduling.dispatch_eligible?(issue, ["Todo"], ["Done"],
             claimed: MapSet.new(),
             running: %{"2" => %{state: "In Progress"}},
             max_concurrent_agents: 1
           )

    refute Scheduling.dispatch_eligible?(issue, ["Todo"], ["Done"],
             claimed: MapSet.new(),
             running: %{"2" => %{state: "Todo"}},
             max_concurrent_agents: 10,
             max_concurrent_agents_by_state: %{"todo" => 1}
           )
  end

  defp issue(id, identifier, attrs) do
    struct!(
      Issue,
      Keyword.merge(
        [
          id: id,
          identifier: identifier,
          title: "Title #{identifier}",
          state: "Todo"
        ],
        attrs
      )
    )
  end
end
