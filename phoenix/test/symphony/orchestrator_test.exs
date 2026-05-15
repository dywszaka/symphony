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

  test "runner on_message updates running metadata and token totals" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, _pid, ^issue}

    token_payload = %{
      "threadId" => "thread-1",
      "turnId" => "turn-1",
      "tokenUsage" => %{
        "total" => %{
          "inputTokens" => 10,
          "outputTokens" => 5,
          "totalTokens" => 15
        }
      }
    }

    send(
      server,
      {:codex_update, "issue-1", %{event: :thread_token_usage_updated, payload: token_payload}}
    )

    rate_limits = %{"primary" => %{"usedPercent" => 42}}

    send(
      server,
      {:codex_update, "issue-1",
       %{event: :account_rate_limits_updated, payload: %{"rateLimits" => rate_limits}}}
    )

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.running["issue-1"].codex_total_tokens == 15
    end)

    {:ok, snapshot} = Orchestrator.snapshot(server)
    running = snapshot.running["issue-1"]
    assert running.session_id == "thread-1-turn-1"
    assert running.last_codex_event == "account_rate_limits_updated"
    assert running.codex_input_tokens == 10
    assert running.codex_output_tokens == 5
    assert running.codex_total_tokens == 15
    assert snapshot.codex_totals.input_tokens == 10
    assert snapshot.codex_totals.output_tokens == 5
    assert snapshot.codex_totals.total_tokens == 15
    assert snapshot.codex_rate_limits == rate_limits
  end

  test "dispatch injects codex update callback into runner opts" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!(runner: __MODULE__.CallbackRunner)

    assert :ok = Orchestrator.dispatch_once(server)

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.running["issue-1"].last_codex_event == "turn_started"
    end)
  end

  test "reconfigure updates future scheduling settings and runner prompt template" do
    Memory.put_issues([
      issue("issue-1", "MT-1", state: "Todo"),
      issue("issue-2", "MT-2", state: "Todo")
    ])

    server = start_orchestrator!(settings: settings(max_concurrent_agents: 1))

    updated_settings = settings(max_concurrent_agents: 2, poll_interval_ms: 75)

    assert :ok =
             Orchestrator.reconfigure(server, updated_settings, "Prompt {{ issue.identifier }}")

    assert :ok = Orchestrator.dispatch_once(server)

    assert_receive {:fake_runner_started, _pid1, %Issue{id: "issue-1"}}
    assert_receive {:fake_runner_started, _pid2, %Issue{id: "issue-2"}}

    {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.max_concurrent_agents == 2
    assert snapshot.poll_interval_ms == 75
  end

  test "token totals use deltas from repeated total usage updates" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])
    server = start_orchestrator!()

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, _pid, ^issue}

    send_token_update(server, "issue-1", 10, 5, 15)
    send_token_update(server, "issue-1", 14, 8, 22)

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.codex_totals.total_tokens == 22
    end)

    {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.codex_totals.input_tokens == 14
    assert snapshot.codex_totals.output_tokens == 8
    assert snapshot.codex_totals.total_tokens == 22
  end

  test "reconciliation stalls inactive codex sessions and schedules retry" do
    issue = issue("issue-1", "MT-1")
    Memory.put_issues([issue])

    server =
      start_orchestrator!(settings: settings(stall_timeout_ms: 1), failure_retry_base_ms: 10)

    assert :ok = Orchestrator.dispatch_once(server)
    assert_receive {:fake_runner_started, pid, ^issue}
    Process.sleep(5)

    monitor_ref = Process.monitor(pid)
    assert :ok = Orchestrator.reconcile_once(server)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}

    retry = retry_entry(server, "issue-1")
    assert retry.attempt == 1
    assert retry.error == "codex session stalled"
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
        ),
      codex: %{
        stall_timeout_ms: Keyword.get(overrides, :stall_timeout_ms, 300_000)
      }
    }
  end

  defp send_token_update(server, issue_id, input_tokens, output_tokens, total_tokens) do
    send(server, {
      :codex_update,
      issue_id,
      %{
        event: :thread_token_usage_updated,
        payload: %{
          "threadId" => "thread-1",
          "turnId" => "turn-1",
          "tokenUsage" => %{
            "total" => %{
              "inputTokens" => input_tokens,
              "outputTokens" => output_tokens,
              "totalTokens" => total_tokens
            }
          }
        }
      }
    })
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

  defmodule CallbackRunner do
    @behaviour Symphony.Runner.Behaviour

    @impl true
    def start_issue(issue, opts) do
      on_message = Keyword.fetch!(opts, :on_message)

      pid =
        spawn(fn ->
          on_message.(%{
            event: :turn_started,
            payload: %{"threadId" => "thread-callback", "turnId" => "turn-callback"}
          })

          receive do
            :stop -> :ok
          end
        end)

      send(Keyword.fetch!(opts, :recipient), {:fake_runner_started, pid, issue})
      {:ok, pid}
    end
  end
end
