defmodule Symphony.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, orchestrator_opts} <- Symphony.Runtime.orchestrator_opts() do
      children = [
        {Symphony.Orchestrator, orchestrator_opts},
        SymphonyWeb.Endpoint
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: Symphony.Supervisor)
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    SymphonyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
