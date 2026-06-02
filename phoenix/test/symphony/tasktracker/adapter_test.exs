defmodule Symphony.TaskTracker.AdapterTest do
  use ExUnit.Case, async: true

  alias Symphony.TaskTracker.Adapter
  alias Symphony.Tracker.Issue

  @settings %{
    tracker: %{
      endpoint: "http://tasktracker.example/api/v1",
      api_key: "task-token",
      project_key: "platform",
      active_states: ["Todo", "In Progress"],
      terminal_states: ["Done", "Canceled"]
    }
  }

  test "fetch_candidate_issues filters by project key and active states" do
    parent = self()

    request_fun = fn method, url, headers, params, json ->
      send(parent, {:request, method, url, headers, params, json})
      {:ok, %{status: 200, body: %{"data" => [task("task-1", "TT-1")]}}}
    end

    assert {:ok, [%Issue{} = issue]} =
             Adapter.fetch_candidate_issues(@settings, request_fun: request_fun)

    assert issue.id == "task-1"
    assert issue.identifier == "TT-1"
    assert issue.priority == 2
    assert issue.state == "Todo"
    assert issue.branch_name == "tasktracker/TT-1"
    assert issue.labels == ["backend"]
    assert issue.blocked_by == [%{id: "blocker-1", identifier: "TT-0", state: "In Progress"}]
    assert issue.created_at == ~U[2026-01-01 00:00:00Z]
    assert issue.updated_at == ~U[2026-01-02 00:00:00Z]

    assert_receive {:request, :get, "http://tasktracker.example/api/v1/projects/platform/tasks",
                    headers, params, nil}

    assert {"Authorization", "Bearer task-token"} in headers
    assert params[:state] == "Todo,In Progress"
    assert params[:limit] == 100
  end

  test "fetch_issues_by_states filters blank states" do
    parent = self()

    request_fun = fn _method, _url, _headers, params, _json ->
      send(parent, {:params, params})
      {:ok, %{status: 200, body: %{"data" => []}}}
    end

    assert {:ok, []} =
             Adapter.fetch_issues_by_states(@settings, ["Done", "", "Done"],
               request_fun: request_fun
             )

    assert_receive {:params, params}
    assert params[:state] == "Done"

    assert {:ok, []} =
             Adapter.fetch_issues_by_states(@settings, ["", " "], request_fun: request_fun)
  end

  test "fetch_issue_states_by_ids requests ids and preserves caller order" do
    parent = self()

    request_fun = fn method, url, headers, params, json ->
      send(parent, {:request, method, url, headers, params, json})

      {:ok,
       %{
         status: 200,
         body: %{"data" => [task("task-2", "TT-2"), task("task-1", "TT-1")]}
       }}
    end

    assert {:ok, [%Issue{id: "task-1"}, %Issue{id: "task-2"}]} =
             Adapter.fetch_issue_states_by_ids(@settings, ["task-1", "", "task-2", "task-1"],
               request_fun: request_fun
             )

    assert_receive {:request, :get, "http://tasktracker.example/api/v1/tasks/by_ids", headers,
                    params, nil}

    assert {"Authorization", "Bearer task-token"} in headers
    assert params[:ids] == "task-1,task-2"
  end

  test "maps request, status, malformed payload, and missing settings errors" do
    assert {:error, {:tasktracker_api_request, :timeout}} =
             Adapter.fetch_candidate_issues(@settings,
               request_fun: fn _method, _url, _headers, _params, _json -> {:error, :timeout} end
             )

    assert {:error, {:tasktracker_api_status, 500, "bad"}} =
             Adapter.fetch_candidate_issues(@settings,
               request_fun: fn _method, _url, _headers, _params, _json ->
                 {:ok, %{status: 500, body: "bad"}}
               end
             )

    assert {:error, :tasktracker_unknown_payload} =
             Adapter.fetch_candidate_issues(@settings,
               request_fun: fn _method, _url, _headers, _params, _json ->
                 {:ok, %{status: 200, body: %{"tasks" => []}}}
               end
             )

    missing_token_settings = put_in(@settings, [:tracker, :api_key], nil)

    assert {:error, :missing_tasktracker_api_token} =
             Adapter.fetch_candidate_issues(missing_token_settings)
  end

  test "write APIs create comments, update state, and update workpad" do
    parent = self()

    request_fun = fn method, url, headers, params, json ->
      send(parent, {:request, method, url, headers, params, json})
      {:ok, %{status: 200, body: %{}}}
    end

    assert :ok =
             Adapter.create_comment(@settings, "task-1", "Started work", request_fun: request_fun)

    assert_receive {:request, :post, "http://tasktracker.example/api/v1/tasks/task-1/comments",
                    headers, [], %{author: "symphony", body: "Started work"}}

    assert {"Authorization", "Bearer task-token"} in headers

    assert :ok =
             Adapter.update_issue_state(@settings, "task-1", "In Progress",
               request_fun: request_fun
             )

    assert_receive {:request, :patch, "http://tasktracker.example/api/v1/tasks/task-1/state",
                    _headers, [], %{actor: "symphony", state: "In Progress"}}

    assert :ok =
             Adapter.update_workpad(@settings, "task-1", "Current workpad",
               request_fun: request_fun
             )

    assert_receive {:request, :patch, "http://tasktracker.example/api/v1/tasks/task-1/workpad",
                    _headers, [], %{actor: "symphony", body: "Current workpad"}}
  end

  defp task(id, identifier) do
    %{
      "id" => id,
      "identifier" => identifier,
      "title" => "Title #{identifier}",
      "description" => "Body",
      "priority" => "2",
      "state" => %{"name" => "Todo"},
      "branch_name" => "tasktracker/#{identifier}",
      "url" => "http://tasktracker.example/tasks/#{identifier}",
      "labels" => ["Backend"],
      "blocked_by" => [
        %{"id" => "blocker-1", "identifier" => "TT-0", "state" => "In Progress"}
      ],
      "created_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-02T00:00:00Z"
    }
  end
end
