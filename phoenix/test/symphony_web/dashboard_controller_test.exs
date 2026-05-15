defmodule SymphonyWeb.DashboardControllerTest do
  use SymphonyWeb.ConnCase, async: false

  test "GET / renders the dashboard shell with orchestrator counters", %{conn: conn} do
    conn = get(conn, "/")
    body = html_response(conn, 200)

    assert body =~ "Symphony"
    assert body =~ "System online"
    assert body =~ "Running"
    assert body =~ "Claimed"
    assert body =~ "Completed"
    assert body =~ "Max concurrency"
    assert body =~ "30s poll interval"
  end
end
