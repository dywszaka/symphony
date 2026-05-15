defmodule Symphony.E2E.LocalOrchestrationTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator
  alias Symphony.Tracker.{Issue, Memory}

  setup do
    Memory.reset()
    :ok
  end

  test "memory tracker dispatches, records codex updates, and queues continuation retry" do
    issue = %Issue{id: "issue-1", identifier: "MT-1", title: "E2E work", state: "Todo"}
    Memory.put_issues([issue])

    server =
      start_supervised!(
        {Orchestrator,
         name: :local_e2e_orchestrator,
         tracker: Memory,
         runner: __MODULE__.Runner,
         runner_opts: [recipient: self()],
         continuation_retry_delay_ms: 50,
         settings: settings()}
      )

    assert :ok = Orchestrator.dispatch_once(:local_e2e_orchestrator)
    assert_receive {:e2e_runner_started, pid, ^issue}

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(:local_e2e_orchestrator)
      snapshot.codex_totals.total_tokens == 9
    end)

    {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.running["issue-1"].session_id == "thread-e2e-turn-e2e"
    assert snapshot.running["issue-1"].codex_input_tokens == 4
    assert snapshot.running["issue-1"].codex_output_tokens == 5

    send(pid, :finish)

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.retry_attempts["issue-1"] && snapshot.retry_attempts["issue-1"].attempt == 1
    end)
  end

  defp settings do
    %{
      polling: %{interval_ms: 30_000},
      tracker: %{
        active_states: ["Todo", "In Progress"],
        terminal_states: ["Done", "Closed"]
      },
      agent: %{
        max_concurrent_agents: 10,
        max_retry_backoff_ms: 300_000,
        max_concurrent_agents_by_state: %{}
      },
      codex: %{stall_timeout_ms: 300_000}
    }
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

  defmodule Runner do
    @behaviour Symphony.Runner.Behaviour

    @impl true
    def start_issue(issue, opts) do
      recipient = Keyword.fetch!(opts, :recipient)
      on_message = Keyword.fetch!(opts, :on_message)

      pid =
        spawn(fn ->
          send(recipient, {:e2e_runner_started, self(), issue})

          on_message.(%{
            event: :thread_token_usage_updated,
            payload: %{
              "threadId" => "thread-e2e",
              "turnId" => "turn-e2e",
              "tokenUsage" => %{
                "total" => %{"inputTokens" => 4, "outputTokens" => 5, "totalTokens" => 9}
              }
            }
          })

          receive do
            :finish -> :ok
          end
        end)

      {:ok, pid}
    end
  end
end
