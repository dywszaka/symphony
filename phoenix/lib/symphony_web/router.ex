defmodule SymphonyWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", SymphonyWeb do
    pipe_through(:browser)

    get("/", DashboardController, :show)
  end

  scope "/", SymphonyWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/api/v1/state", StateController, :show)
  end
end
