defmodule SymphonyWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SymphonyWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/api/v1/state", StateController, :show)
  end
end
