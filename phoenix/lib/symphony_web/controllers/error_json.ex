defmodule SymphonyWeb.ErrorJSON do
  @moduledoc false

  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
