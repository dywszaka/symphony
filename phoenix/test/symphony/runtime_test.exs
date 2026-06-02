defmodule Symphony.RuntimeTest do
  use ExUnit.Case, async: false

  alias Symphony.Runtime

  setup do
    original = Application.get_env(:symphony, :linear_settings)
    original_tasktracker = Application.get_env(:symphony, :tasktracker_settings)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:symphony, :linear_settings)
        value -> Application.put_env(:symphony, :linear_settings, value)
      end

      case original_tasktracker do
        nil -> Application.delete_env(:symphony, :tasktracker_settings)
        value -> Application.put_env(:symphony, :tasktracker_settings, value)
      end
    end)

    :ok
  end

  test "keeps development defaults when WORKFLOW_PATH is not set" do
    assert {:ok, []} = Runtime.orchestrator_opts(%{})
    assert Application.get_env(:symphony, :linear_settings) == nil
    assert Application.get_env(:symphony, :tasktracker_settings) == nil
  end

  test "loads workflow path into a Linear-backed Codex orchestrator" do
    token_name = "SYMPHONY_RUNTIME_LINEAR_TOKEN_#{System.unique_integer([:positive])}"
    System.put_env(token_name, "linear-token")

    on_exit(fn -> System.delete_env(token_name) end)

    workflow_path =
      temp_workflow!("""
      ---
      tracker:
        kind: linear
        project_slug: symphony
        api_key: $#{token_name}
        active_states:
          - Todo
      polling:
        interval_ms: 250
      workspace:
        root: tmp/workspaces
      agent:
        max_concurrent_agents: 2
      codex:
        command: echo fake-codex
      ---

      Work on {{ issue.identifier }}: {{ issue.title }}
      """)

    assert {:ok, opts} = Runtime.orchestrator_opts(%{"WORKFLOW_PATH" => workflow_path})

    assert Keyword.fetch!(opts, :tracker) == Symphony.Linear.Adapter
    assert Keyword.fetch!(opts, :runner) == Symphony.Runner.Codex
    assert Keyword.fetch!(opts, :auto_poll) == true

    settings = Keyword.fetch!(opts, :settings)
    assert settings.tracker.kind == "linear"
    assert settings.tracker.api_key == "linear-token"
    assert settings.tracker.project_slug == "symphony"
    assert settings.polling.interval_ms == 250
    assert settings.agent.max_concurrent_agents == 2

    assert Keyword.fetch!(opts, :runner_opts) == [
             prompt_template: "Work on {{ issue.identifier }}: {{ issue.title }}",
             tracker: Symphony.Linear.Adapter
           ]

    assert Application.get_env(:symphony, :linear_settings) == settings
    assert Application.get_env(:symphony, :tasktracker_settings) == nil
  end

  test "loads workflow path into a TaskTracker-backed Codex orchestrator" do
    token_name = "SYMPHONY_RUNTIME_TASKTRACKER_TOKEN_#{System.unique_integer([:positive])}"
    System.put_env(token_name, "task-token")

    on_exit(fn -> System.delete_env(token_name) end)

    workflow_path =
      temp_workflow!("""
      ---
      tracker:
        kind: tasktracker
        project_key: platform
        api_key: $#{token_name}
        active_states:
          - Todo
      codex:
        command: echo fake-codex
      ---

      Work on {{ issue.identifier }}: {{ issue.title }}
      """)

    assert {:ok, opts} = Runtime.orchestrator_opts(%{"WORKFLOW_PATH" => workflow_path})

    assert Keyword.fetch!(opts, :tracker) == Symphony.TaskTracker.Adapter
    assert Keyword.fetch!(opts, :runner) == Symphony.Runner.Codex

    settings = Keyword.fetch!(opts, :settings)
    assert settings.tracker.kind == "tasktracker"
    assert settings.tracker.api_key == "task-token"
    assert settings.tracker.project_key == "platform"
    assert settings.tracker.endpoint == "http://localhost:4001/api/v1"

    assert Keyword.fetch!(opts, :runner_opts) == [
             prompt_template: "Work on {{ issue.identifier }}: {{ issue.title }}",
             tracker: Symphony.TaskTracker.Adapter
           ]

    assert Application.get_env(:symphony, :linear_settings) == nil
    assert Application.get_env(:symphony, :tasktracker_settings) == settings
  end

  test "returns a startup error for invalid workflow dispatch settings" do
    workflow_path =
      temp_workflow!("""
      ---
      tracker:
        kind: linear
      ---

      Work on {{ issue.identifier }}.
      """)

    assert {:error, {:invalid_runtime_workflow, :missing_linear_api_token}} =
             Runtime.orchestrator_opts(%{"WORKFLOW_PATH" => workflow_path})
  end

  defp temp_workflow!(content) do
    dir =
      Path.join(System.tmp_dir!(), "symphony-runtime-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "WORKFLOW.md")
    File.write!(path, content)
    path
  end
end
