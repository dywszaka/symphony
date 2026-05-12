defmodule SymphonyWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint SymphonyWeb.Endpoint
      import Phoenix.ConnTest
      import Plug.Conn
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
