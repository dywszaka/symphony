defmodule SymphonyWeb.RefreshControllerTest do
  use SymphonyWeb.ConnCase, async: false

  test "POST /api/v1/refresh triggers a best-effort poll", %{conn: conn} do
    conn = post(conn, "/api/v1/refresh")

    assert json_response(conn, 202) == %{
             "queued" => true,
             "reconciled" => true,
             "dispatched" => true
           }
  end
end
