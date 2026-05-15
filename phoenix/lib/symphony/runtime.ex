defmodule Symphony.Runtime do
  @moduledoc """
  Builds runtime wiring from process environment.

  Without `WORKFLOW_PATH`, Symphony starts in the lightweight local development
  mode used by tests and the dashboard. With `WORKFLOW_PATH`, the workflow file
  becomes the runtime contract for tracker, runner, prompt, and polling config.
  """

  alias Symphony.Config.Settings
  alias Symphony.Workflow.Loader

  @app :symphony
  @linear_settings_key :linear_settings

  @spec orchestrator_opts(map()) :: {:ok, keyword()} | {:error, term()}
  def orchestrator_opts(env \\ System.get_env()) when is_map(env) do
    case workflow_path(env) do
      nil ->
        Application.delete_env(@app, @linear_settings_key)
        {:ok, []}

      path ->
        build_workflow_opts(path)
    end
  end

  defp workflow_path(env) do
    env
    |> Map.get("WORKFLOW_PATH")
    |> case do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _other ->
        nil
    end
  end

  defp build_workflow_opts(path) do
    with {:ok, workflow} <- Loader.load(path),
         {:ok, settings} <- Settings.from_workflow(workflow, path),
         :ok <- Settings.validate_dispatch(settings),
         {:ok, tracker} <- tracker_module(settings.tracker.kind) do
      configure_tracker(settings)

      {:ok,
       [
         settings: settings,
         tracker: tracker,
         runner: Symphony.Runner.Codex,
         runner_opts: [prompt_template: workflow.prompt_template, tracker: tracker],
         auto_poll: true
       ]}
    else
      {:error, reason} -> {:error, {:invalid_runtime_workflow, reason}}
      reason -> {:error, {:invalid_runtime_workflow, reason}}
    end
  end

  defp tracker_module("linear"), do: {:ok, Symphony.Linear.Adapter}
  defp tracker_module("memory"), do: {:ok, Symphony.Tracker.Memory}
  defp tracker_module(kind), do: {:error, {:unsupported_tracker_kind, kind}}

  defp configure_tracker(%Settings{tracker: %{kind: "linear"}} = settings) do
    Application.put_env(@app, @linear_settings_key, settings)
  end

  defp configure_tracker(_settings) do
    Application.delete_env(@app, @linear_settings_key)
  end
end
