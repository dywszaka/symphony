defmodule Symphony.Linear.AdapterTest do
  use ExUnit.Case, async: true

  alias Symphony.Linear.Adapter
  alias Symphony.Tracker.Issue

  @settings %{
    tracker: %{
      endpoint: "https://linear.example/graphql",
      api_key: "linear-token",
      project_slug: "proj",
      active_states: ["Todo", "In Progress"],
      terminal_states: ["Done", "Canceled"]
    }
  }

  test "fetch_candidate_issues uses project slug filter, paginates, and normalizes issues" do
    parent = self()

    post_fun = fn endpoint, headers, query, variables ->
      send(parent, {:request, endpoint, headers, query, variables})

      case variables["after"] do
        nil ->
          {:ok, %{status: 200, body: page([linear_issue("issue-1", "MT-1")], true, "cursor-1")}}

        "cursor-1" ->
          {:ok, %{status: 200, body: page([linear_issue("issue-2", "MT-2")], false, nil)}}
      end
    end

    assert {:ok, [%Issue{} = first, %Issue{} = second]} =
             Adapter.fetch_candidate_issues(@settings, post_fun: post_fun)

    assert first.identifier == "MT-1"
    assert first.state == "Todo"
    assert first.labels == ["backend"]
    assert first.blocked_by == [%{id: "blocker-1", identifier: "MT-0", state: "In Progress"}]
    assert first.created_at == ~U[2026-01-01 00:00:00Z]
    assert first.updated_at == ~U[2026-01-02 00:00:00Z]
    assert second.identifier == "MT-2"

    assert_receive {:request, "https://linear.example/graphql", headers, query, variables}
    assert {"Authorization", "linear-token"} in headers
    assert query =~ "slugId: { eq: $projectSlug }"
    assert variables["projectSlug"] == "proj"
    assert variables["activeStates"] == ["Todo", "In Progress"]
    assert variables["first"] == 50

    assert_receive {:request, _endpoint, _headers, _query, %{"after" => "cursor-1"}}
  end

  test "fetch_issue_states_by_ids uses GraphQL ID list typing" do
    parent = self()

    post_fun = fn _endpoint, _headers, query, variables ->
      send(parent, {:query, query, variables})

      {:ok,
       %{
         status: 200,
         body: %{"data" => %{"issues" => %{"nodes" => [linear_issue("issue-1", "MT-1")]}}}
       }}
    end

    assert {:ok, [%Issue{id: "issue-1"}]} =
             Adapter.fetch_issue_states_by_ids(@settings, ["issue-1"], post_fun: post_fun)

    assert_receive {:query, query, %{"ids" => ["issue-1"]}}
    assert query =~ "$ids: [ID!]"
  end

  test "fetch_issues_by_states filters by project slug and state names" do
    parent = self()

    post_fun = fn _endpoint, _headers, query, variables ->
      send(parent, {:query, query, variables})

      {:ok,
       %{
         status: 200,
         body: %{"data" => %{"issues" => %{"nodes" => [linear_issue("issue-1", "MT-1")]}}}
       }}
    end

    assert {:ok, [%Issue{id: "issue-1"}]} =
             Adapter.fetch_issues_by_states(@settings, ["Done"], post_fun: post_fun)

    assert_receive {:query, query, %{"projectSlug" => "proj", "stateNames" => ["Done"]}}
    assert query =~ "slugId: { eq: $projectSlug }"
  end

  test "maps request, status, graphql, malformed payload, and pagination errors" do
    assert {:error, {:linear_api_request, :timeout}} =
             Adapter.fetch_candidate_issues(@settings,
               post_fun: fn _endpoint, _headers, _query, _variables -> {:error, :timeout} end
             )

    assert {:error, {:linear_api_status, 500, "bad"}} =
             Adapter.fetch_candidate_issues(@settings,
               post_fun: fn _endpoint, _headers, _query, _variables ->
                 {:ok, %{status: 500, body: "bad"}}
               end
             )

    assert {:error, {:linear_graphql_errors, [%{"message" => "no"}]}} =
             Adapter.fetch_candidate_issues(@settings,
               post_fun: fn _endpoint, _headers, _query, _variables ->
                 {:ok, %{status: 200, body: %{"errors" => [%{"message" => "no"}]}}}
               end
             )

    assert {:error, {:linear_unknown_payload, _payload}} =
             Adapter.fetch_candidate_issues(@settings,
               post_fun: fn _endpoint, _headers, _query, _variables ->
                 {:ok, %{status: 200, body: %{"data" => %{}}}}
               end
             )

    assert {:error, :linear_missing_end_cursor} =
             Adapter.fetch_candidate_issues(@settings,
               post_fun: fn _endpoint, _headers, _query, _variables ->
                 {:ok, %{status: 200, body: page([], true, nil)}}
               end
             )
  end

  defp page(nodes, has_next_page, end_cursor) do
    %{
      "data" => %{
        "issues" => %{
          "nodes" => nodes,
          "pageInfo" => %{"hasNextPage" => has_next_page, "endCursor" => end_cursor}
        }
      }
    }
  end

  defp linear_issue(id, identifier) do
    %{
      "id" => id,
      "identifier" => identifier,
      "title" => "Title #{identifier}",
      "description" => "Body",
      "priority" => 1,
      "state" => %{"name" => "Todo"},
      "branchName" => "branch/#{identifier}",
      "url" => "https://linear.example/#{identifier}",
      "labels" => %{"nodes" => [%{"name" => "Backend"}]},
      "inverseRelations" => %{
        "nodes" => [
          %{
            "type" => "blocks",
            "issue" => %{
              "id" => "blocker-1",
              "identifier" => "MT-0",
              "state" => %{"name" => "In Progress"}
            }
          }
        ]
      },
      "createdAt" => "2026-01-01T00:00:00Z",
      "updatedAt" => "2026-01-02T00:00:00Z"
    }
  end
end
