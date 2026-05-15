defmodule Symphony.Orchestrator.StartupCleanupTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator
  alias Symphony.Tracker.Issue
  alias Symphony.Workspace

  setup do
    Application.put_env(:symphony, :cleanup_tracker_response, {:ok, []})

    on_exit(fn ->
      Application.delete_env(:symphony, :cleanup_tracker_response)
    end)

    :ok
  end

  test "removes workspaces for terminal issues during startup" do
    root = temp_root!()
    assert {:ok, %{path: done_path}} = Workspace.create_for_issue("MT-1", root)
    assert File.dir?(done_path)

    Application.put_env(:symphony, :cleanup_tracker_response, {
      :ok,
      [%Issue{id: "issue-1", identifier: "MT-1", state: "Done"}]
    })

    start_supervised!(
      {Orchestrator,
       name: :startup_cleanup_test, tracker: __MODULE__.Tracker, settings: settings(root)}
    )

    refute File.exists?(done_path)
  end

  test "cleanup tracker errors do not abort startup" do
    root = temp_root!()
    Application.put_env(:symphony, :cleanup_tracker_response, {:error, :tracker_down})

    assert pid =
             start_supervised!(
               {Orchestrator,
                name: :startup_cleanup_error_test,
                tracker: __MODULE__.Tracker,
                settings: settings(root)}
             )

    assert Process.alive?(pid)
  end

  defp settings(root) do
    %{
      polling: %{interval_ms: 30_000},
      workspace: %{root: root},
      hooks: %{timeout_ms: 1_000},
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

  defp temp_root! do
    path =
      Path.join(
        System.tmp_dir!(),
        "symphony-startup-cleanup-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defmodule Tracker do
    @behaviour Symphony.Tracker.Behaviour

    @impl true
    def fetch_candidate_issues, do: {:ok, []}

    @impl true
    def fetch_issues_by_states(_states),
      do: Application.fetch_env!(:symphony, :cleanup_tracker_response)

    @impl true
    def fetch_issue_states_by_ids(_ids), do: {:ok, []}
  end
end
