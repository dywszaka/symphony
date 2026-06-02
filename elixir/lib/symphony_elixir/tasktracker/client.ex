defmodule SymphonyElixir.TaskTracker.Client do
  @moduledoc """
  REST client for the local TaskTracker service.
  """

  require Logger

  alias SymphonyElixir.{Config, Linear.Issue}

  @default_limit 100
  @actor "symphony"

  @spec fetch_candidate_issues(keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(opts \\ []) do
    tracker = tracker_settings(opts)

    with :ok <- validate_tracker(tracker) do
      fetch_tasks_by_states(tracker.active_states, opts)
    end
  end

  @spec fetch_issues_by_states([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names, opts \\ []) when is_list(state_names) do
    state_names
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.uniq()
    |> case do
      [] -> {:ok, []}
      states -> fetch_tasks_by_states(states, opts)
    end
  end

  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) do
    ids =
      issue_ids
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.uniq()

    case ids do
      [] ->
        {:ok, []}

      ids ->
        tracker = tracker_settings(opts)

        with :ok <- validate_tracker(tracker),
             {:ok, body} <- request(:get, "/tasks/by_ids", [ids: Enum.join(ids, ",")], nil, tracker, opts),
             {:ok, issues} <- decode_task_page(body, tracker) do
          {:ok, sort_issues_by_requested_ids(issues, ids)}
        end
    end
  end

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, opts \\ []) when is_binary(issue_id) and is_binary(body) do
    tracker = tracker_settings(opts)

    with :ok <- validate_tracker(tracker),
         {:ok, _body} <-
           request(
             :post,
             "/tasks/#{URI.encode(issue_id)}/comments",
             [],
             %{author: @actor, body: body},
             tracker,
             opts
           ) do
      :ok
    end
  end

  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name, opts \\ [])
      when is_binary(issue_id) and is_binary(state_name) do
    tracker = tracker_settings(opts)

    with :ok <- validate_tracker(tracker),
         {:ok, _body} <-
           request(
             :patch,
             "/tasks/#{URI.encode(issue_id)}/state",
             [],
             %{actor: @actor, state: state_name},
             tracker,
             opts
           ) do
      :ok
    end
  end

  @spec update_workpad(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_workpad(issue_id, body, opts \\ []) when is_binary(issue_id) and is_binary(body) do
    tracker = tracker_settings(opts)

    with :ok <- validate_tracker(tracker),
         {:ok, _body} <-
           request(
             :patch,
             "/tasks/#{URI.encode(issue_id)}/workpad",
             [],
             %{actor: @actor, body: body},
             tracker,
             opts
           ) do
      :ok
    end
  end

  defp fetch_tasks_by_states(states, opts) do
    tracker = tracker_settings(opts)

    with :ok <- validate_tracker(tracker),
         {:ok, body} <-
           request(
             :get,
             "/projects/#{URI.encode(tracker.project_key)}/tasks",
             [state: Enum.join(states, ","), limit: @default_limit],
             nil,
             tracker,
             opts
           ) do
      decode_task_page(body, tracker)
    end
  end

  defp request(method, path, params, json, tracker, opts) do
    request_fun = Keyword.get(opts, :request_fun, &Req.request/1)

    request_opts =
      [
        method: method,
        url: endpoint_url(tracker.endpoint, path),
        params: params,
        headers: request_headers(tracker),
        connect_options: [timeout: 30_000]
      ]
      |> maybe_put_json(json)

    case request_fun.(request_opts) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:tasktracker_api_status, status, body}}

      {:error, reason} ->
        Logger.error("TaskTracker request failed: #{inspect(reason)}")
        {:error, {:tasktracker_api_request, reason}}
    end
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, json), do: Keyword.put(opts, :json, json)

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

  defp decode_task_page(%{"data" => tasks}, tracker) when is_list(tasks) do
    {:ok, Enum.map(tasks, &normalize_task(&1, tracker))}
  end

  defp decode_task_page(_body, _tracker), do: {:error, :tasktracker_unknown_payload}

  defp normalize_task(task, tracker) when is_map(task) do
    assignee = task["assignee"]

    %Issue{
      id: task["id"],
      identifier: task["identifier"],
      title: task["title"],
      description: task["description"],
      priority: parse_priority(task["priority"]),
      state: get_in(task, ["state", "name"]),
      branch_name: task["branch_name"],
      url: task["url"],
      assignee_id: assignee,
      blocked_by: normalize_blockers(task["blocked_by"]),
      labels: normalize_labels(task["labels"]),
      assigned_to_worker: assigned_to_worker?(assignee, tracker.assignee),
      created_at: parse_datetime(task["created_at"]),
      updated_at: parse_datetime(task["updated_at"])
    }
  end

  defp normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&String.downcase/1)
  end

  defp normalize_labels(_labels), do: []

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

  defp assigned_to_worker?(_assignee, nil), do: true

  defp assigned_to_worker?(assignee, configured_assignee)
       when is_binary(assignee) and is_binary(configured_assignee) do
    String.trim(assignee) == String.trim(configured_assignee)
  end

  defp assigned_to_worker?(_assignee, _configured_assignee), do: false

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_raw), do: nil

  defp parse_priority(priority) when is_integer(priority), do: priority

  defp parse_priority(priority) when is_binary(priority) do
    case Integer.parse(priority) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp parse_priority(_priority), do: nil

  defp sort_issues_by_requested_ids(issues, ids) do
    order = ids |> Enum.with_index() |> Map.new()
    fallback = map_size(order)

    Enum.sort_by(issues, fn %Issue{id: id} -> Map.get(order, id, fallback) end)
  end

  defp validate_tracker(tracker) do
    cond do
      not is_binary(tracker.endpoint) or String.trim(tracker.endpoint) == "" ->
        {:error, :missing_tasktracker_endpoint}

      not is_binary(tracker.api_key) or String.trim(tracker.api_key) == "" ->
        {:error, :missing_tasktracker_api_token}

      not is_binary(tracker.project_key) or String.trim(tracker.project_key) == "" ->
        {:error, :missing_tasktracker_project_key}

      true ->
        :ok
    end
  end

  defp tracker_settings(opts) do
    case Keyword.fetch(opts, :tracker) do
      {:ok, tracker} -> tracker
      :error -> Config.settings!().tracker
    end
  end
end
