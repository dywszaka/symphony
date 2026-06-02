defmodule Symphony.Codex.DynamicToolTest do
  use ExUnit.Case, async: true

  alias Symphony.Codex.DynamicTool

  test "tool_specs advertises TaskTracker write contracts" do
    specs_by_name = Map.new(DynamicTool.tool_specs(), &{&1["name"], &1})

    assert specs_by_name["tasktracker_create_comment"]["inputSchema"]["required"] == [
             "issue_id",
             "body"
           ]

    assert specs_by_name["tasktracker_update_state"]["inputSchema"]["required"] == [
             "issue_id",
             "state"
           ]

    assert specs_by_name["tasktracker_update_workpad"]["inputSchema"]["required"] == [
             "issue_id",
             "body"
           ]
  end

  test "TaskTracker tools call tracker write APIs" do
    parent = self()

    tracker = %{
      create_comment: fn issue_id, body ->
        send(parent, {:create_comment, issue_id, body})
        :ok
      end,
      update_issue_state: fn issue_id, state ->
        send(parent, {:update_issue_state, issue_id, state})
        :ok
      end,
      update_workpad: fn issue_id, body ->
        send(parent, {:update_workpad, issue_id, body})
        :ok
      end
    }

    assert %{"success" => true} =
             DynamicTool.execute(
               "tasktracker_create_comment",
               %{"issue_id" => "task-1", "body" => "Started work"},
               tracker: tracker
             )

    assert_received {:create_comment, "task-1", "Started work"}

    assert %{"success" => true} =
             DynamicTool.execute(
               "tasktracker_update_state",
               %{"issue_id" => "task-1", "state" => "In Progress"},
               tracker: tracker
             )

    assert_received {:update_issue_state, "task-1", "In Progress"}

    assert %{"success" => true} =
             DynamicTool.execute(
               "tasktracker_update_workpad",
               %{"issue_id" => "task-1", "body" => "Current workpad"},
               tracker: tracker
             )

    assert_received {:update_workpad, "task-1", "Current workpad"}
  end

  test "validates TaskTracker tool arguments and formats errors" do
    tracker = %{
      create_comment: fn _issue_id, _body -> flunk("tracker should not be called") end
    }

    response =
      DynamicTool.execute(
        "tasktracker_create_comment",
        %{"issue_id" => "task-1", "body" => " "},
        tracker: tracker
      )

    assert response["success"] == false

    assert Jason.decode!(response["output"]) == %{
             "error" => %{
               "message" =>
                 "`tasktracker_create_comment` requires non-empty string arguments: issue_id, body."
             }
           }

    invalid = DynamicTool.execute("tasktracker_update_workpad", "bad", tracker: tracker)

    assert Jason.decode!(invalid["output"]) == %{
             "error" => %{
               "message" =>
                 "`tasktracker_update_workpad` expects a JSON object with string fields: issue_id, body."
             }
           }
  end

  test "unsupported tools include supported TaskTracker tool names" do
    response = DynamicTool.execute("unknown_tool", %{})

    assert response["success"] == false

    assert Jason.decode!(response["output"]) == %{
             "error" => %{
               "message" => ~s(Unsupported dynamic tool: "unknown_tool".),
               "supportedTools" => [
                 "tasktracker_create_comment",
                 "tasktracker_update_state",
                 "tasktracker_update_workpad"
               ]
             }
           }
  end
end
