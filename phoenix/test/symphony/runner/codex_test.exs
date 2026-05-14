defmodule Symphony.Runner.CodexTest do
  use ExUnit.Case, async: false

  alias Symphony.Runner.Codex
  alias Symphony.Tracker.Issue

  setup do
    root = tmp_dir("workspaces")
    test_pid = self()
    Application.put_env(:symphony, :fake_codex_test_pid, test_pid)
    Application.put_env(:symphony, :fake_tracker_refreshes, [])

    on_exit(fn ->
      Application.delete_env(:symphony, :fake_codex_test_pid)
      Application.delete_env(:symphony, :fake_tracker_refreshes)
    end)

    {:ok, root: root}
  end

  test "runs first prompt and continuation turns while the issue remains active", %{root: root} do
    issue = %Issue{id: "issue-1", identifier: "MT-1", title: "Build runner", state: "Todo"}

    Application.put_env(:symphony, :fake_tracker_refreshes, [
      %Issue{issue | state: "In Progress"},
      %Issue{issue | state: "Done"}
    ])

    assert :ok =
             Codex.run_issue(issue,
               settings: settings(root, max_turns: 3),
               prompt_template:
                 "Ticket {{ issue.identifier }} {{ issue.title }} attempt={{ attempt }}",
               attempt: 2,
               app_server: __MODULE__.FakeAppServer,
               tracker: __MODULE__.FakeTracker
             )

    workspace = Path.join(root, "MT-1")
    assert File.dir?(workspace)

    assert_received {:start_session, ^workspace}
    assert_received {:run_turn, "Ticket MT-1 Build runner attempt=2", "MT-1"}
    assert_received {:run_turn, continuation_prompt, "MT-1"}
    assert continuation_prompt =~ "continuation turn #2 of 3"
    refute continuation_prompt =~ "Ticket MT-1 Build runner"
    assert_received {:stop_session, "thread-1"}
  end

  test "respects agent max_turns when the issue remains active", %{root: root} do
    issue = %Issue{id: "issue-2", identifier: "MT-2", title: "Keep running", state: "Todo"}

    Application.put_env(:symphony, :fake_tracker_refreshes, [%Issue{issue | state: "In Progress"}])

    assert :ok =
             Codex.run_issue(issue,
               settings: settings(root, max_turns: 1),
               prompt_template: "Ticket {{ issue.identifier }}",
               app_server: __MODULE__.FakeAppServer,
               tracker: __MODULE__.FakeTracker
             )

    assert_received {:run_turn, "Ticket MT-2", "MT-2"}
    refute_receive {:run_turn, _continuation_prompt, "MT-2"}, 20
  end

  test "before_run hook failure aborts before app-server launch", %{root: root} do
    issue = %Issue{id: "issue-3", identifier: "MT-3", title: "Blocked hook", state: "Todo"}

    assert {:error, {:hook_failed, :before_run, 6, _output}} =
             Codex.run_issue(issue,
               settings: settings(root, max_turns: 1, hooks: %{before_run: "exit 6"}),
               prompt_template: "Ticket {{ issue.identifier }}",
               app_server: __MODULE__.FakeAppServer,
               tracker: __MODULE__.FakeTracker
             )

    refute_received {:start_session, _workspace}
  end

  test "after_run hook is best effort", %{root: root} do
    issue = %Issue{id: "issue-4", identifier: "MT-4", title: "After hook", state: "Todo"}
    marker = Path.join([root, "MT-4", "after.txt"])

    assert :ok =
             Codex.run_issue(issue,
               settings:
                 settings(root,
                   max_turns: 1,
                   hooks: %{after_run: "echo after > #{shell_escape(marker)} && exit 5"}
                 ),
               prompt_template: "Ticket {{ issue.identifier }}",
               app_server: __MODULE__.FakeAppServer,
               tracker: __MODULE__.FakeTracker
             )

    assert String.trim(File.read!(marker)) == "after"
    assert_received {:stop_session, "thread-1"}
  end

  test "rejects unsafe workspace cwd before app-server launch", %{root: root} do
    issue = %Issue{id: "issue-5", identifier: nil, title: "Unsafe cwd", state: "Todo"}

    assert {:error, {:invalid_issue_identifier, nil}} =
             Codex.run_issue(issue,
               settings: settings(root, max_turns: 1),
               prompt_template: "Ticket",
               app_server: __MODULE__.FakeAppServer,
               tracker: __MODULE__.FakeTracker
             )

    refute_received {:start_session, _workspace}
  end

  defp settings(root, opts) do
    %{
      workspace: %{root: root},
      hooks: Map.merge(%{timeout_ms: 1_000}, Keyword.get(opts, :hooks, %{})),
      tracker: %{active_states: ["Todo", "In Progress"], terminal_states: ["Done"]},
      agent: %{max_turns: Keyword.fetch!(opts, :max_turns)},
      codex: %{command: "codex app-server"}
    }
  end

  defp tmp_dir(name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "symphony-runner-#{name}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp shell_escape(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"

  defmodule FakeAppServer do
    def start_session(workspace, _settings) do
      send(test_pid(), {:start_session, workspace})
      {:ok, %{thread_id: "thread-1", workspace: workspace}}
    end

    def run_turn(session, prompt, issue, _opts \\ []) do
      send(test_pid(), {:run_turn, prompt, issue.identifier})
      {:ok, %{thread_id: session.thread_id, turn_id: System.unique_integer([:positive])}}
    end

    def stop_session(session) do
      send(test_pid(), {:stop_session, session.thread_id})
      :ok
    end

    defp test_pid, do: Application.fetch_env!(:symphony, :fake_codex_test_pid)
  end

  defmodule FakeTracker do
    def fetch_issue_states_by_ids([_issue_id]) do
      case Application.fetch_env!(:symphony, :fake_tracker_refreshes) do
        [issue | rest] ->
          Application.put_env(:symphony, :fake_tracker_refreshes, rest)
          {:ok, [issue]}

        [] ->
          {:ok, []}
      end
    end
  end
end
