defmodule Symphony.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator
  alias Symphony.Tracker.{Issue, Memory}

  setup do
    Memory.reset()
    :ok
  end

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

  test "dispatches eligible memory issues and tracks claimed running state" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, _pid, ^issue}

    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.claimed == ["issue-1"]
    assert Map.keys(snapshot.running) == ["issue-1"]
    assert snapshot.running["issue-1"].identifier == "MT-1"
    assert snapshot.running["issue-1"].state == "Todo"
  end

  test "auto poll dispatches candidates on the configured interval" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    _server = start_orchestrator!(auto_poll: true, settings: settings(poll_interval_ms: 20))

    assert_receive {:fake_runner_started, _pid, ^issue}, 200
  end

  test "dispatch respects global and per-state concurrency limits" do
    Memory.put_issues([
      issue("issue-1", "MT-1", state: "Todo"),
      issue("issue-2", "MT-2", state: "Todo"),
      issue("issue-3", "MT-3", state: "In Progress")
    ])

    server =
      start_orchestrator!(
        settings:
          settings(max_concurrent_agents: 2, max_concurrent_agents_by_state: %{"todo" => 1})
      )

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, _pid1, %Issue{id: "issue-1"}}
    assert_receive {:fake_runner_started, _pid2, %Issue{id: "issue-3"}}
    refute_receive {:fake_runner_started, _pid3, %Issue{id: "issue-2"}}, 50

    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert Map.keys(snapshot.running) |> Enum.sort() == ["issue-1", "issue-3"]
  end

  test "normal worker exit schedules continuation retry" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!(continuation_retry_delay_ms: 50)

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}

    send(pid, :finish)
    assert_eventually(fn -> retry_entry(server, "issue-1") end)

    retry = retry_entry(server, "issue-1")
    assert retry.attempt == 1
    assert retry.identifier == "MT-1"
    assert retry.error == nil
  end

  test "abnormal worker exit schedules exponential backoff retry" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!(failure_retry_base_ms: 10_000)

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}

    send(pid, {:crash, :boom})
    assert_eventually(fn -> retry_entry(server, "issue-1") end)

    retry = retry_entry(server, "issue-1")
    assert retry.attempt == 1
    assert retry.error == "agent exited: :boom"
  end

  test "retry releases claim when issue is no longer a candidate" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}
    send(pid, {:crash, :boom})
    assert_eventually(fn -> retry_entry(server, "issue-1") end)

    Memory.reset()
    assert :ok = Orchestrator.retry_now(server, "issue-1")

    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.claimed == []
    assert snapshot.retry_attempts == %{}
  end

  test "retry redispatches the issue when it is still an eligible candidate" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}
    send(pid, {:crash, :boom})
    assert_eventually(fn -> retry_entry(server, "issue-1") end)

    assert :ok = Orchestrator.retry_now(server, "issue-1")
    assert_receive {:fake_runner_started, _retry_pid, ^issue}

    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert Map.keys(snapshot.running) == ["issue-1"]
    assert snapshot.retry_attempts == %{}
    assert snapshot.claimed == ["issue-1"]
  end

  test "reconciliation releases terminal and non-active issues while refreshing active issues" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}

    Memory.put_issues([%{issue | state: "In Progress", title: "Updated"}])
    assert :ok = Orchestrator.reconcile_once(server)
    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.running["issue-1"].state == "In Progress"
    assert snapshot.running["issue-1"].title == "Updated"

    Memory.put_issues([%{issue | state: "Review"}])
    monitor_ref = Process.monitor(pid)
    assert :ok = Orchestrator.reconcile_once(server)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}
    assert {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.running == %{}
    assert snapshot.claimed == []
  end

  defp start_orchestrator!(opts \\ []) do
    name = :"orchestrator_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Orchestrator,
       Keyword.merge(
         [
           name: name,
           tracker: Memory,
           runner: Symphony.Support.FakeRunner,
           runner_opts: [recipient: self()],
           settings: settings()
         ],
         opts
       )}
    )

    name
  end

  defp settings(overrides \\ []) do
    agent_overrides =
      Keyword.take(overrides, [:max_concurrent_agents, :max_concurrent_agents_by_state])

    %{
      polling: %{
        interval_ms: Keyword.get(overrides, :poll_interval_ms, 30_000)
      },
      tracker: %{
        active_states: ["Todo", "In Progress"],
        terminal_states: ["Done", "Closed", "Canceled", "Cancelled", "Duplicate"]
      },
      agent:
        Map.merge(
          %{
            max_concurrent_agents: 10,
            max_retry_backoff_ms: 300_000,
            max_concurrent_agents_by_state: %{}
          },
          Map.new(agent_overrides)
        )
    }
  end

  defp retry_entry(server, issue_id) do
    {:ok, snapshot} = Orchestrator.snapshot(server)
    snapshot.retry_attempts[issue_id]
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0),
    do: flunk("condition did not become true, last value: #{inspect(fun.())}")

  defp issue(id, identifier, attrs \\ []) do
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
