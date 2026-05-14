defmodule Symphony.Linear.Adapter do
  @moduledoc """
  Linear-compatible tracker adapter.
  """

  @behaviour Symphony.Tracker.Behaviour

  alias Symphony.Linear.Client
  alias Symphony.Tracker.Issue

  @page_size 50
  @issue_fields """
  id
  identifier
  title
  description
  priority
  state { name }
  branchName
  url
  labels { nodes { name } }
  inverseRelations { nodes { type issue { id identifier state { name } } } }
  createdAt
  updatedAt
  """

  @candidate_query """
  query SymphonyLinearCandidateIssues($projectSlug: String!, $activeStates: [String!], $first: Int!, $after: String) {
    issues(
      filter: { project: { slugId: { eq: $projectSlug } }, state: { name: { in: $activeStates } } }
      first: $first
      after: $after
    ) {
      nodes {
        #{@issue_fields}
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
  """

  @states_query """
  query SymphonyLinearIssuesByStates($projectSlug: String!, $stateNames: [String!]) {
    issues(filter: { project: { slugId: { eq: $projectSlug } }, state: { name: { in: $stateNames } } }) {
      nodes {
        #{@issue_fields}
      }
    }
  }
  """

  @ids_query """
  query SymphonyLinearIssuesById($ids: [ID!]) {
    issues(filter: { id: { in: $ids } }) {
      nodes {
        #{@issue_fields}
      }
    }
  }
  """

  @impl true
  def fetch_candidate_issues do
    with {:ok, settings} <- runtime_settings() do
      fetch_candidate_issues(settings)
    end
  end

  @spec fetch_candidate_issues(map(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(settings, opts \\ []) do
    fetch_candidate_page(settings, opts, nil, [])
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
    variables = %{"projectSlug" => tracker(settings).project_slug, "stateNames" => states}

    with {:ok, body} <- request(settings, @states_query, variables, opts),
         {:ok, nodes} <- issue_nodes(body) do
      {:ok, Enum.map(nodes, &normalize_issue/1)}
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
  def fetch_issue_states_by_ids(settings, ids, opts \\ [])

  def fetch_issue_states_by_ids(_settings, [], _opts), do: {:ok, []}

  def fetch_issue_states_by_ids(settings, ids, opts) when is_list(ids) do
    with {:ok, body} <- request(settings, @ids_query, %{"ids" => ids}, opts),
         {:ok, nodes} <- issue_nodes(body) do
      {:ok, Enum.map(nodes, &normalize_issue/1)}
    end
  end

  defp fetch_candidate_page(settings, opts, after_cursor, acc) do
    variables = %{
      "projectSlug" => tracker(settings).project_slug,
      "activeStates" => tracker(settings).active_states,
      "first" => @page_size,
      "after" => after_cursor
    }

    with {:ok, body} <- request(settings, @candidate_query, variables, opts),
         {:ok, %{"nodes" => nodes, "pageInfo" => page_info}} <- issues_connection(body) do
      issues = acc ++ Enum.map(nodes, &normalize_issue/1)

      case page_info do
        %{"hasNextPage" => true, "endCursor" => cursor} when is_binary(cursor) and cursor != "" ->
          fetch_candidate_page(settings, opts, cursor, issues)

        %{"hasNextPage" => true} ->
          {:error, :linear_missing_end_cursor}

        _ ->
          {:ok, issues}
      end
    end
  end

  defp request(settings, query, variables, opts) do
    post_fun = Keyword.get(opts, :post_fun, &Client.post/4)
    headers = [{"Authorization", tracker(settings).api_key}]

    case post_fun.(tracker(settings).endpoint, headers, query, variables) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        decode_graphql_body(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:linear_api_status, status, body}}

      {:error, reason} ->
        {:error, {:linear_api_request, reason}}
    end
  end

  defp decode_graphql_body(%{"errors" => errors}) when is_list(errors),
    do: {:error, {:linear_graphql_errors, errors}}

  defp decode_graphql_body(%{"data" => _data} = body), do: {:ok, body}
  defp decode_graphql_body(body), do: {:error, {:linear_unknown_payload, body}}

  defp issues_connection(%{
         "data" => %{"issues" => %{"nodes" => nodes, "pageInfo" => page_info} = connection}
       })
       when is_list(nodes) and is_map(page_info),
       do: {:ok, connection}

  defp issues_connection(body), do: {:error, {:linear_unknown_payload, body}}

  defp issue_nodes(%{"data" => %{"issues" => %{"nodes" => nodes}}}) when is_list(nodes),
    do: {:ok, nodes}

  defp issue_nodes(body), do: {:error, {:linear_unknown_payload, body}}

  defp normalize_issue(raw) when is_map(raw) do
    Issue.normalize(%{
      id: raw["id"],
      identifier: raw["identifier"],
      title: raw["title"],
      description: raw["description"],
      priority: integer_or_nil(raw["priority"]),
      state: get_in(raw, ["state", "name"]),
      branch_name: raw["branchName"],
      url: raw["url"],
      labels: normalize_labels(raw),
      blocked_by: normalize_blockers(raw),
      created_at: parse_datetime(raw["createdAt"]),
      updated_at: parse_datetime(raw["updatedAt"])
    })
  end

  defp normalize_labels(raw) do
    raw
    |> get_in(["labels", "nodes"])
    |> case do
      labels when is_list(labels) -> Enum.map(labels, & &1["name"])
      _ -> []
    end
  end

  defp normalize_blockers(raw) do
    raw
    |> get_in(["inverseRelations", "nodes"])
    |> case do
      relations when is_list(relations) ->
        relations
        |> Enum.filter(&(String.downcase(to_string(&1["type"])) == "blocks"))
        |> Enum.map(fn relation ->
          issue = relation["issue"] || %{}

          %{
            id: issue["id"],
            identifier: issue["identifier"],
            state: get_in(issue, ["state", "name"])
          }
        end)

      _ ->
        []
    end
  end

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_value), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp tracker(%{tracker: tracker}), do: tracker

  defp runtime_settings do
    case Application.get_env(:symphony, :linear_settings) do
      nil -> {:error, :missing_linear_settings}
      settings -> {:ok, settings}
    end
  end
end
