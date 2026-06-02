defmodule SymphonyElixir.TaskTracker.ClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.TaskTracker.Client

  setup do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tasktracker",
      tracker_endpoint: "http://tracker.example/api/v1",
      tracker_api_token: "task-token",
      tracker_project_key: "platform",
      tracker_project_slug: nil,
      tracker_active_states: ["Todo", "In Progress"],
      tracker_terminal_states: ["Done", "Cancelled"]
    )

    :ok
  end

  test "fetch_candidate_issues reads project tasks and normalizes them" do
    parent = self()

    request_fun = fn opts ->
      send(parent, {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => [
             tasktracker_task(%{
               "id" => "task-1",
               "identifier" => "PLATFORM-1",
               "state" => %{"name" => "Todo"},
               "blocked_by" => [
                 %{"id" => "task-0", "identifier" => "PLATFORM-0", "state" => "Done"}
               ]
             })
           ]
         }
       }}
    end

    assert {:ok, [%Issue{} = issue]} = Client.fetch_candidate_issues(request_fun: request_fun)

    assert issue.id == "task-1"
    assert issue.identifier == "PLATFORM-1"
    assert issue.state == "Todo"
    assert issue.branch_name == "codex/platform-1"
    assert issue.url == "http://tracker.example/tasks/PLATFORM-1"
    assert issue.labels == ["backend"]
    assert issue.blocked_by == [%{id: "task-0", identifier: "PLATFORM-0", state: "Done"}]
    assert issue.created_at == ~U[2026-05-01 10:00:00Z]

    assert_receive {:request, opts}
    assert opts[:method] == :get
    assert opts[:url] == "http://tracker.example/api/v1/projects/platform/tasks"
    assert opts[:params] == [state: "Todo,In Progress", limit: 100]
    assert {"Authorization", "Bearer task-token"} in opts[:headers]
  end

  test "fetch_issues_by_states reads requested state list" do
    parent = self()

    request_fun = fn opts ->
      send(parent, {:request, opts})
      {:ok, %Req.Response{status: 200, body: %{"data" => []}}}
    end

    assert {:ok, []} = Client.fetch_issues_by_states(["Review", "Done"], request_fun: request_fun)

    assert_receive {:request, opts}
    assert opts[:url] == "http://tracker.example/api/v1/projects/platform/tasks"
    assert opts[:params] == [state: "Review,Done", limit: 100]
  end

  test "fetch_issue_states_by_ids preserves requested id order" do
    request_fun = fn opts ->
      assert opts[:method] == :get
      assert opts[:url] == "http://tracker.example/api/v1/tasks/by_ids"
      assert opts[:params] == [ids: "task-2,task-1"]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => [
             tasktracker_task(%{"id" => "task-2", "identifier" => "PLATFORM-2"}),
             tasktracker_task(%{"id" => "task-1", "identifier" => "PLATFORM-1"})
           ]
         }
       }}
    end

    assert {:ok, issues} =
             Client.fetch_issue_states_by_ids(["task-2", "task-1"], request_fun: request_fun)

    assert Enum.map(issues, & &1.id) == ["task-2", "task-1"]
  end

  test "mutations write comments and state changes" do
    parent = self()

    request_fun = fn opts ->
      send(parent, {:request, opts})
      {:ok, %Req.Response{status: 200, body: %{}}}
    end

    assert :ok = Client.create_comment("task-1", "Agent finished", request_fun: request_fun)

    assert_receive {:request, comment_opts}
    assert comment_opts[:method] == :post
    assert comment_opts[:url] == "http://tracker.example/api/v1/tasks/task-1/comments"
    assert comment_opts[:json] == %{author: "symphony", body: "Agent finished"}

    assert :ok = Client.update_issue_state("task-1", "Done", request_fun: request_fun)

    assert_receive {:request, state_opts}
    assert state_opts[:method] == :patch
    assert state_opts[:url] == "http://tracker.example/api/v1/tasks/task-1/state"
    assert state_opts[:json] == %{actor: "symphony", state: "Done"}
  end

  test "mutation updates workpad" do
    parent = self()

    request_fun = fn opts ->
      send(parent, {:request, opts})
      {:ok, %Req.Response{status: 200, body: %{}}}
    end

    assert :ok = Client.update_workpad("task-1", "Current workpad", request_fun: request_fun)

    assert_receive {:request, workpad_opts}
    assert workpad_opts[:method] == :patch
    assert workpad_opts[:url] == "http://tracker.example/api/v1/tasks/task-1/workpad"
    assert workpad_opts[:json] == %{actor: "symphony", body: "Current workpad"}
  end

  test "reports http and malformed payload errors" do
    assert {:error, {:tasktracker_api_status, 500, %{"error" => "bad"}}} =
             Client.fetch_candidate_issues(
               request_fun: fn _opts ->
                 {:ok, %Req.Response{status: 500, body: %{"error" => "bad"}}}
               end
             )

    assert {:error, :tasktracker_unknown_payload} =
             Client.fetch_candidate_issues(
               request_fun: fn _opts ->
                 {:ok, %Req.Response{status: 200, body: %{"items" => []}}}
               end
             )

    assert {:error, {:tasktracker_api_request, :timeout}} =
             Client.fetch_candidate_issues(request_fun: fn _opts -> {:error, :timeout} end)
  end

  defp tasktracker_task(overrides) do
    Map.merge(
      %{
        "id" => "task-1",
        "identifier" => "PLATFORM-1",
        "title" => "Build TaskTracker integration",
        "description" => "Replace Linear polling",
        "priority" => 2,
        "state" => %{"name" => "Todo"},
        "assignee" => "agent-a",
        "branch_name" => "codex/platform-1",
        "labels" => ["Backend"],
        "url" => "http://tracker.example/tasks/PLATFORM-1",
        "blocked_by" => [],
        "created_at" => "2026-05-01T10:00:00Z",
        "updated_at" => "2026-05-01T11:00:00Z"
      },
      overrides
    )
  end
end
