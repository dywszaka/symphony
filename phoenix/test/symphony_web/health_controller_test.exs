defmodule SymphonyWeb.HealthControllerTest do
  use SymphonyWeb.ConnCase, async: true

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
