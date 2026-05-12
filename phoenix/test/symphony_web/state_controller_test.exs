defmodule SymphonyWeb.StateControllerTest do
  use SymphonyWeb.ConnCase, async: false

  test "GET /api/v1/state returns orchestrator snapshot", %{conn: conn} do
    conn = get(conn, "/api/v1/state")
    body = json_response(conn, 200)

    assert body["poll_interval_ms"] == 30_000
    assert body["max_concurrent_agents"] == 10
    assert body["running"] == %{}
    assert body["claimed"] == []
    assert body["retry_attempts"] == %{}
    assert body["completed"] == []

    assert body["codex_totals"] == %{
             "input_tokens" => 0,
             "output_tokens" => 0,
             "total_tokens" => 0,
             "seconds_running" => 0
           }
  end
end
