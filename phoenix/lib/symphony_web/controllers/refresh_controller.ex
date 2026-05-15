defmodule SymphonyWeb.RefreshController do
  use Phoenix.Controller, formats: [:json]

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    :ok = Symphony.Orchestrator.reconcile_once()
    :ok = Symphony.Orchestrator.dispatch_once()

    conn
    |> put_status(:accepted)
    |> json(%{queued: true, reconciled: true, dispatched: true})
  end
end
