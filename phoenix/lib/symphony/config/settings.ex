defmodule Symphony.Config.Settings do
  @moduledoc """
  Typed runtime settings derived from workflow front matter.
  """

  defstruct tracker: %{},
            polling: %{},
            workspace: %{},
            hooks: %{},
            agent: %{},
            codex: %{}

  @type t :: %__MODULE__{}

  @spec from_workflow(%{config: map()}, Path.t()) :: {:ok, t()} | {:error, term()}
  def from_workflow(%{config: config}, workflow_path)
      when is_map(config) and is_binary(workflow_path) do
    normalized = normalize_keys(config)

    settings = %__MODULE__{
      tracker: tracker_settings(Map.get(normalized, "tracker", %{})),
      polling: polling_settings(Map.get(normalized, "polling", %{})),
      workspace: workspace_settings(Map.get(normalized, "workspace", %{}), workflow_path),
      hooks: hooks_settings(Map.get(normalized, "hooks", %{})),
      agent: agent_settings(Map.get(normalized, "agent", %{})),
      codex: codex_settings(Map.get(normalized, "codex", %{}))
    }

    {:ok, settings}
  rescue
    error in ArgumentError -> {:error, {:invalid_workflow_config, Exception.message(error)}}
  end

  @spec validate_dispatch(t()) :: :ok | {:error, term()}
  def validate_dispatch(%__MODULE__{} = settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      settings.tracker.kind not in ["linear", "memory", "tasktracker"] ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      settings.tracker.kind == "linear" and blank?(settings.tracker.api_key) ->
        {:error, :missing_linear_api_token}

      settings.tracker.kind == "linear" and blank?(settings.tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      settings.tracker.kind == "tasktracker" and blank?(settings.tracker.api_key) ->
        {:error, :missing_tasktracker_api_token}

      settings.tracker.kind == "tasktracker" and blank?(settings.tracker.project_key) ->
        {:error, :missing_tasktracker_project_key}

      blank?(settings.codex.command) ->
        {:error, {:invalid_workflow_config, "codex.command can't be blank"}}

      true ->
        :ok
    end
  end

  defp tracker_settings(raw) do
    kind = string_or_nil(raw["kind"])

    %{
      kind: kind,
      endpoint: tracker_endpoint(kind, raw["endpoint"]),
      api_key: tracker_api_key(kind, raw["api_key"]),
      project_slug: string_or_nil(raw["project_slug"]),
      project_key: string_or_nil(raw["project_key"]),
      active_states: string_list(raw["active_states"], ["Todo", "In Progress"]),
      terminal_states:
        string_list(raw["terminal_states"], [
          "Closed",
          "Cancelled",
          "Canceled",
          "Duplicate",
          "Done"
        ])
    }
  end

  defp tracker_endpoint("tasktracker", value),
    do: string_or_nil(value) || "http://localhost:4001/api/v1"

  defp tracker_endpoint(_kind, value),
    do: string_or_nil(value) || "https://api.linear.app/graphql"

  defp tracker_api_key("tasktracker", value),
    do: resolve_secret(value, System.get_env("TASKTRACKER_TOKEN"))

  defp tracker_api_key(_kind, value),
    do: resolve_secret(value, System.get_env("LINEAR_API_KEY"))

  defp polling_settings(raw),
    do: %{interval_ms: positive_integer(raw["interval_ms"], 30_000, "polling.interval_ms")}

  defp workspace_settings(raw, workflow_path) do
    root =
      raw
      |> Map.get("root", Path.join(System.tmp_dir!(), "symphony_workspaces"))
      |> resolve_path(Path.dirname(workflow_path))

    %{root: root}
  end

  defp hooks_settings(raw),
    do: %{timeout_ms: positive_integer(raw["timeout_ms"], 60_000, "hooks.timeout_ms")}

  defp agent_settings(raw) do
    %{
      max_concurrent_agents:
        positive_integer(raw["max_concurrent_agents"], 10, "agent.max_concurrent_agents"),
      max_turns: positive_integer(raw["max_turns"], 20, "agent.max_turns"),
      max_retry_backoff_ms:
        positive_integer(raw["max_retry_backoff_ms"], 300_000, "agent.max_retry_backoff_ms"),
      max_concurrent_agents_by_state:
        normalize_state_limits(raw["max_concurrent_agents_by_state"])
    }
  end

  defp codex_settings(raw) do
    %{
      command: string_or_nil(raw["command"]) || "codex app-server",
      approval_policy: raw["approval_policy"],
      thread_sandbox: raw["thread_sandbox"],
      turn_sandbox_policy: raw["turn_sandbox_policy"],
      turn_timeout_ms:
        positive_integer(raw["turn_timeout_ms"], 3_600_000, "codex.turn_timeout_ms"),
      read_timeout_ms: positive_integer(raw["read_timeout_ms"], 5_000, "codex.read_timeout_ms"),
      stall_timeout_ms:
        non_negative_integer(raw["stall_timeout_ms"], 300_000, "codex.stall_timeout_ms")
    }
  end

  defp normalize_keys(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {to_string(key), normalize_keys(val)} end)

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp string_or_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp string_or_nil(_value), do: nil

  defp string_list(nil, default), do: default
  defp string_list(values, _default) when is_list(values), do: Enum.map(values, &to_string/1)
  defp string_list(_values, _default), do: raise(ArgumentError, "state lists must be arrays")

  defp positive_integer(nil, default, _field), do: default
  defp positive_integer(value, _default, _field) when is_integer(value) and value > 0, do: value

  defp positive_integer(_value, _default, field),
    do: raise(ArgumentError, "#{field} must be a positive integer")

  defp non_negative_integer(nil, default, _field), do: default

  defp non_negative_integer(value, _default, _field) when is_integer(value) and value >= 0,
    do: value

  defp non_negative_integer(_value, _default, field),
    do: raise(ArgumentError, "#{field} must be a non-negative integer")

  defp resolve_secret(nil, fallback), do: normalize_secret(fallback)

  defp resolve_secret(value, fallback) when is_binary(value),
    do: value |> resolve_env_reference(fallback) |> normalize_secret()

  defp resolve_secret(_value, _fallback), do: nil

  defp normalize_secret(value) when is_binary(value), do: if(value == "", do: nil, else: value)
  defp normalize_secret(_value), do: nil

  defp resolve_path(value, workflow_dir) when is_binary(value) do
    value
    |> resolve_env_reference(nil)
    |> case do
      nil ->
        Path.join(System.tmp_dir!(), "symphony_workspaces")

      "" ->
        Path.join(System.tmp_dir!(), "symphony_workspaces")

      "~" ->
        System.user_home!()

      "~/" <> rest ->
        Path.join(System.user_home!(), rest)

      path ->
        if Path.type(path) == :relative,
          do: Path.expand(path, workflow_dir),
          else: Path.expand(path)
    end
  end

  defp resolve_path(_value, _workflow_dir),
    do: Path.join(System.tmp_dir!(), "symphony_workspaces")

  defp resolve_env_reference("$" <> env_name, fallback) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, env_name) do
      case System.get_env(env_name) do
        nil -> fallback
        "" -> nil
        value -> value
      end
    else
      "$" <> env_name
    end
  end

  defp resolve_env_reference(value, _fallback), do: value

  defp normalize_state_limits(nil), do: %{}

  defp normalize_state_limits(limits) when is_map(limits) do
    Map.new(limits, fn {state, limit} ->
      unless is_integer(limit) and limit > 0,
        do:
          raise(
            ArgumentError,
            "agent.max_concurrent_agents_by_state values must be positive integers"
          )

      {state |> to_string() |> String.downcase(), limit}
    end)
  end

  defp normalize_state_limits(_limits),
    do: raise(ArgumentError, "agent.max_concurrent_agents_by_state must be a map")

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
