defmodule Symphony.Runner.Codex do
  @moduledoc """
  Runner that executes an issue through Codex app-server turns.
  """

  @behaviour Symphony.Runner.Behaviour

  alias Symphony.Codex.AppServer
  alias Symphony.Orchestrator.Scheduling
  alias Symphony.Prompt.Template
  alias Symphony.Tracker.Issue
  alias Symphony.Workspace
  alias Symphony.Workspace.Hooks

  @continuation_prompt """
  The previous Codex turn completed normally, but the tracker issue is still in an active state.

  This is continuation turn #%{turn_number} of %{max_turns} for the current agent run.
  The original task instructions and prior turn context are already present in this thread.
  Continue the remaining ticket work without restating the original prompt.
  """

  @impl true
  def start_issue(%Issue{} = issue, opts) when is_list(opts) do
    Task.start(fn ->
      case run_issue(issue, opts) do
        :ok -> :ok
        {:error, reason} -> exit({:codex_runner_failed, reason})
      end
    end)
  end

  @spec run_issue(Issue.t(), keyword()) :: :ok | {:error, term()}
  def run_issue(%Issue{} = issue, opts) when is_list(opts) do
    with :ok <- validate_issue_identifier(issue.identifier) do
      settings = Keyword.fetch!(opts, :settings)
      prompt_template = Keyword.get(opts, :prompt_template, "")
      attempt = Keyword.get(opts, :attempt)
      app_server = Keyword.get(opts, :app_server, AppServer)
      tracker = Keyword.get(opts, :tracker, Symphony.Tracker.Memory)
      on_message = Keyword.get(opts, :on_message, fn _message -> :ok end)

      with {:ok, workspace} <-
             Workspace.create_for_issue(issue.identifier, settings.workspace.root, settings.hooks),
           :ok <- validate_workspace_cwd(workspace.path, settings.workspace.root),
           :ok <-
             Hooks.run(
               :before_run,
               Map.get(settings.hooks, :before_run),
               workspace.path,
               settings.hooks.timeout_ms
             ),
           {:ok, session} <- app_server.start_session(workspace.path, settings) do
        result =
          run_turns(
            session,
            issue,
            prompt_template,
            attempt,
            settings,
            app_server,
            tracker,
            on_message,
            1
          )

        app_server.stop_session(session)
        run_after_run(settings, workspace.path)
        result
      end
    end
  end

  defp run_turns(
         session,
         issue,
         prompt_template,
         attempt,
         settings,
         app_server,
         tracker,
         on_message,
         turn_number
       ) do
    with {:ok, prompt} <-
           prompt_for_turn(prompt_template, issue, attempt, turn_number, settings.agent.max_turns),
         {:ok, _turn_result} <-
           app_server.run_turn(session, prompt, issue, on_message: on_message),
         {:ok, refreshed_issue} <- refresh_issue(tracker, issue) do
      if continue?(refreshed_issue, settings, turn_number) do
        run_turns(
          session,
          refreshed_issue,
          prompt_template,
          attempt,
          settings,
          app_server,
          tracker,
          on_message,
          turn_number + 1
        )
      else
        :ok
      end
    end
  end

  defp prompt_for_turn(prompt_template, issue, attempt, 1, _max_turns),
    do: Template.render(prompt_template, issue, attempt: attempt)

  defp prompt_for_turn(_prompt_template, _issue, _attempt, turn_number, max_turns) do
    {:ok,
     @continuation_prompt
     |> String.trim()
     |> String.replace("%{turn_number}", to_string(turn_number))
     |> String.replace("%{max_turns}", to_string(max_turns))}
  end

  defp refresh_issue(tracker, issue) do
    case tracker.fetch_issue_states_by_ids([issue.id]) do
      {:ok, [refreshed | _rest]} -> {:ok, refreshed}
      {:ok, []} -> {:ok, issue}
      {:error, reason} -> {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue?(issue, settings, turn_number) do
    turn_number < settings.agent.max_turns and
      Scheduling.active_state?(issue.state, settings.tracker.active_states)
  end

  defp run_after_run(settings, workspace_path) do
    Hooks.run(
      :after_run,
      Map.get(settings.hooks, :after_run),
      workspace_path,
      settings.hooks.timeout_ms
    )

    :ok
  end

  defp validate_issue_identifier(identifier) when is_binary(identifier) do
    if String.trim(identifier) == "",
      do: {:error, {:invalid_issue_identifier, identifier}},
      else: :ok
  end

  defp validate_issue_identifier(identifier),
    do: {:error, {:invalid_issue_identifier, identifier}}

  defp validate_workspace_cwd(workspace_path, root) do
    root_path = Path.expand(root)
    workspace_path = Path.expand(workspace_path)

    if workspace_path != root_path and
         String.starts_with?(workspace_path <> "/", root_path <> "/") do
      :ok
    else
      {:error, {:unsafe_workspace_cwd, workspace_path, root_path}}
    end
  end
end
