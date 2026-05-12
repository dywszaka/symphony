defmodule Symphony.Config.SettingsTest do
  use ExUnit.Case, async: true

  alias Symphony.Config.Settings

  test "applies spec defaults" do
    workflow_path = temp_workflow_path!()

    assert {:ok, settings} =
             Settings.from_workflow(%{config: %{}, prompt_template: ""}, workflow_path)

    assert settings.tracker.endpoint == "https://api.linear.app/graphql"
    assert settings.tracker.active_states == ["Todo", "In Progress"]

    assert settings.tracker.terminal_states == [
             "Closed",
             "Cancelled",
             "Canceled",
             "Duplicate",
             "Done"
           ]

    assert settings.polling.interval_ms == 30_000
    assert settings.workspace.root == Path.join(System.tmp_dir!(), "symphony_workspaces")
    assert settings.hooks.timeout_ms == 60_000
    assert settings.agent.max_concurrent_agents == 10
    assert settings.agent.max_turns == 20
    assert settings.agent.max_retry_backoff_ms == 300_000
    assert settings.agent.max_concurrent_agents_by_state == %{}
    assert settings.codex.command == "codex app-server"
    assert settings.codex.turn_timeout_ms == 3_600_000
    assert settings.codex.read_timeout_ms == 5_000
    assert settings.codex.stall_timeout_ms == 300_000
  end

  test "resolves env-backed secrets and paths" do
    env_name = "SYMPHONY_PHASE1_ROOT_#{System.unique_integer([:positive])}"
    token_name = "SYMPHONY_PHASE1_TOKEN_#{System.unique_integer([:positive])}"
    root = Path.join(System.tmp_dir!(), "phase1-root")
    System.put_env(env_name, root)
    System.put_env(token_name, "secret")

    on_exit(fn ->
      System.delete_env(env_name)
      System.delete_env(token_name)
    end)

    workflow = %{
      config: %{
        "tracker" => %{
          "kind" => "linear",
          "api_key" => "$#{token_name}",
          "project_slug" => "proj"
        },
        "workspace" => %{"root" => "$#{env_name}"}
      },
      prompt_template: ""
    }

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert settings.tracker.api_key == "secret"
    assert settings.workspace.root == Path.expand(root)
  end

  test "resolves relative workspace root from workflow directory" do
    workflow_path = temp_workflow_path!()

    workflow = %{
      config: %{"workspace" => %{"root" => "tmp/workspaces"}},
      prompt_template: ""
    }

    assert {:ok, settings} = Settings.from_workflow(workflow, workflow_path)
    assert settings.workspace.root == Path.expand("tmp/workspaces", Path.dirname(workflow_path))
  end

  test "validates memory tracker without Linear credentials" do
    workflow = %{config: %{"tracker" => %{"kind" => "memory"}}, prompt_template: ""}

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert :ok = Settings.validate_dispatch(settings)
  end

  test "validates Linear dispatch requirements" do
    workflow = %{config: %{"tracker" => %{"kind" => "linear"}}, prompt_template: ""}

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert {:error, :missing_linear_api_token} = Settings.validate_dispatch(settings)
  end

  defp temp_workflow_path! do
    dir =
      Path.join(System.tmp_dir!(), "symphony-settings-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    Path.join(dir, "WORKFLOW.md")
  end
end
