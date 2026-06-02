defmodule Symphony.TaskTracker.Adapter do
  @moduledoc """
  TaskTracker-backed tracker adapter.
  """

  @behaviour Symphony.Tracker.Behaviour

  alias Symphony.TaskTracker.Client
  alias Symphony.Tracker.Issue

  @default_limit 100

  @impl true
  def fetch_candidate_issues do
    with {:ok, settings} <- runtime_settings() do
      fetch_candidate_issues(settings)
    end
  end

  @spec fetch_candidate_issues(map(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(settings, opts \\ []) do
    fetch_tasks_by_states(settings, tracker(settings).active_states, opts)
  end

  @impl true
  def fetch_issues_by_states(states) do
    with {:ok, settings} <- runtime_settings() do
      fetch_issues_by_states(settings, states)
    end
  end

  @spec fetch_issues_by_states(map(), [String.t()], keyword()) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(settings, states, opts \\ []) when is_list(states) do
    case clean_values(states) do
      [] -> {:ok, []}
      states -> fetch_tasks_by_states(settings, states, opts)
    end
  end

  @impl true
  def fetch_issue_states_by_ids(ids) do
    with {:ok, settings} <- runtime_settings() do
      fetch_issue_states_by_ids(settings, ids)
    end
  end

  @spec fetch_issue_states_by_ids(map(), [String.t()], keyword()) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(settings, ids, opts \\ []) when is_list(ids) do
    clean_ids = clean_values(ids)

    case clean_ids do
      [] ->
        {:ok, []}

      ids ->
        with :ok <- validate_tracker(tracker(settings)),
             {:ok, body} <-
               request(settings, :get, "/tasks/by_ids", [ids: Enum.join(ids, ",")], nil, opts),
             {:ok, issues} <- decode_task_page(body) do
          {:ok, sort_issues_by_requested_ids(issues, ids)}
        end
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, settings} <- runtime_settings() do
      create_comment(settings, issue_id, body)
    end
  end

  @spec create_comment(map(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(settings, issue_id, body, opts \\ [])
      when is_binary(issue_id) and is_binary(body) do
    with :ok <- validate_tracker(tracker(settings)),
         {:ok, _body} <-
           request(
             settings,
             :post,
             "/tasks/#{URI.encode(issue_id)}/comments",
             [],
             %{author: "symphony", body: body},
             opts
           ) do
      :ok
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    with {:ok, settings} <- runtime_settings() do
      update_issue_state(settings, issue_id, state_name)
    end
  end

  @spec update_issue_state(map(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(settings, issue_id, state_name, opts \\ [])
      when is_binary(issue_id) and is_binary(state_name) do
    with :ok <- validate_tracker(tracker(settings)),
         {:ok, _body} <-
           request(
             settings,
             :patch,
             "/tasks/#{URI.encode(issue_id)}/state",
             [],
             %{actor: "symphony", state: state_name},
             opts
           ) do
      :ok
    end
  end

  @spec update_workpad(String.t(), String.t()) :: :ok | {:error, term()}
  def update_workpad(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, settings} <- runtime_settings() do
      update_workpad(settings, issue_id, body)
    end
  end

  @spec update_workpad(map(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_workpad(settings, issue_id, body, opts \\ [])
      when is_binary(issue_id) and is_binary(body) do
    with :ok <- validate_tracker(tracker(settings)),
         {:ok, _body} <-
           request(
             settings,
             :patch,
             "/tasks/#{URI.encode(issue_id)}/workpad",
             [],
             %{actor: "symphony", body: body},
             opts
           ) do
      :ok
    end
  end

  defp fetch_tasks_by_states(settings, states, opts) do
    tracker = tracker(settings)

    with :ok <- validate_tracker(tracker),
         {:ok, body} <-
           request(
             settings,
             :get,
             "/projects/#{URI.encode(tracker.project_key)}/tasks",
             [state: Enum.join(states, ","), limit: @default_limit],
             nil,
             opts
           ) do
      decode_task_page(body)
    end
  end

  defp request(settings, method, path, params, json, opts) do
    request_fun = Keyword.get(opts, :request_fun, &Client.request/5)
    tracker = tracker(settings)

    case request_fun.(
           method,
           endpoint_url(tracker.endpoint, path),
           request_headers(tracker),
           params,
           json
         ) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:tasktracker_api_status, status, body}}

      {:error, reason} ->
        {:error, {:tasktracker_api_request, reason}}
    end
  end

  defp request_headers(tracker) do
    [
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{tracker.api_key}"}
    ]
  end

  defp endpoint_url(endpoint, path) do
    endpoint
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end

  defp decode_task_page(%{"data" => tasks}) when is_list(tasks) do
    {:ok, Enum.map(tasks, &normalize_task/1)}
  end

  defp decode_task_page(_body), do: {:error, :tasktracker_unknown_payload}

  defp normalize_task(task) when is_map(task) do
    Issue.normalize(%{
      id: task["id"],
      identifier: task["identifier"],
      title: task["title"],
      description: task["description"],
      priority: integer_or_nil(task["priority"]),
      state: get_in(task, ["state", "name"]),
      branch_name: task["branch_name"],
      url: task["url"],
      labels: task["labels"],
      blocked_by: normalize_blockers(task["blocked_by"]),
      created_at: parse_datetime(task["created_at"]),
      updated_at: parse_datetime(task["updated_at"])
    })
  end

  defp normalize_blockers(blockers) when is_list(blockers) do
    Enum.map(blockers, fn blocker ->
      %{
        id: blocker["id"],
        identifier: blocker["identifier"],
        state: blocker["state"]
      }
    end)
  end

  defp normalize_blockers(_blockers), do: []

  defp integer_or_nil(value) when is_integer(value), do: value

  defp integer_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp integer_or_nil(_value), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp sort_issues_by_requested_ids(issues, ids) do
    order = ids |> Enum.with_index() |> Map.new()
    fallback = map_size(order)

    Enum.sort_by(issues, fn %Issue{id: id} -> Map.get(order, id, fallback) end)
  end

  defp validate_tracker(tracker) do
    cond do
      blank?(tracker.endpoint) ->
        {:error, :missing_tasktracker_endpoint}

      blank?(tracker.api_key) ->
        {:error, :missing_tasktracker_api_token}

      blank?(tracker.project_key) ->
        {:error, :missing_tasktracker_project_key}

      true ->
        :ok
    end
  end

  defp clean_values(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.uniq()
  end

  defp tracker(%{tracker: tracker}), do: tracker

  defp runtime_settings do
    case Application.get_env(:symphony, :tasktracker_settings) do
      nil -> {:error, :missing_tasktracker_settings}
      settings -> {:ok, settings}
    end
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
