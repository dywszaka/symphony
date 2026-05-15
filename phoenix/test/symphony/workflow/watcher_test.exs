defmodule Symphony.Workflow.WatcherTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator
  alias Symphony.Tracker.Memory
  alias Symphony.Workflow.Watcher

  setup do
    Memory.reset()
    :ok
  end

  test "reloads changed workflow settings into the orchestrator" do
    dir = temp_dir!()
    workflow_path = Path.join(dir, "WORKFLOW.md")
    write_workflow!(workflow_path, 1, "Initial prompt")

    server = start_orchestrator!()

    watcher =
      start_supervised!(
        {Watcher, workflow_path: workflow_path, orchestrator: server, poll_interval_ms: 20}
      )

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.max_concurrent_agents == 1
    end)

    write_workflow!(workflow_path, 3, "Reloaded prompt")
    assert :ok = Watcher.reload_now(watcher)

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.max_concurrent_agents == 3
    end)

    assert {:ok, watcher_snapshot} = Watcher.snapshot(watcher)
    assert watcher_snapshot.last_error == nil
    assert watcher_snapshot.prompt_template == "Reloaded prompt"
  end

  test "invalid reload keeps last known good settings and records error" do
    dir = temp_dir!()
    workflow_path = Path.join(dir, "WORKFLOW.md")
    write_workflow!(workflow_path, 2, "Good prompt")

    server = start_orchestrator!()

    watcher =
      start_supervised!(
        {Watcher, workflow_path: workflow_path, orchestrator: server, poll_interval_ms: 20}
      )

    assert_eventually(fn ->
      {:ok, snapshot} = Orchestrator.snapshot(server)
      snapshot.max_concurrent_agents == 2
    end)

    File.write!(
      workflow_path,
      "---\ntracker:\n  kind: memory\nagent:\n  max_concurrent_agents: 0\n---\nBad"
    )

    assert :ok = Watcher.reload_now(watcher)

    {:ok, snapshot} = Orchestrator.snapshot(server)
    assert snapshot.max_concurrent_agents == 2

    assert {:ok, watcher_snapshot} = Watcher.snapshot(watcher)
    assert watcher_snapshot.prompt_template == "Good prompt"
    assert match?({:invalid_workflow_config, _message}, watcher_snapshot.last_error)
  end

  defp start_orchestrator! do
    name = :"watcher_orchestrator_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Orchestrator,
       name: name,
       tracker: Memory,
       runner: Symphony.Support.FakeRunner,
       runner_opts: [recipient: self()],
       settings: %{
         polling: %{interval_ms: 30_000},
         tracker: %{active_states: ["Todo"], terminal_states: ["Done"]},
         agent: %{
           max_concurrent_agents: 1,
           max_retry_backoff_ms: 300_000,
           max_concurrent_agents_by_state: %{}
         },
         codex: %{stall_timeout_ms: 300_000}
       }}
    )

    name
  end

  defp write_workflow!(path, max_concurrent_agents, prompt) do
    File.write!(path, """
    ---
    tracker:
      kind: memory
    polling:
      interval_ms: 250
    agent:
      max_concurrent_agents: #{max_concurrent_agents}
    codex:
      command: codex app-server
    ---
    #{prompt}
    """)
  end

  defp temp_dir! do
    path = Path.join(System.tmp_dir!(), "symphony-watcher-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
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
end
