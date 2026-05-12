defmodule SymphonyWeb.StateController do
  use Phoenix.Controller, formats: [:json]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    case Symphony.Orchestrator.snapshot() do
      {:ok, snapshot} ->
        json(conn, snapshot)

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: to_string(reason)})
    end
  end
end
