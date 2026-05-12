defmodule Symphony.Tracker.Issue do
  @moduledoc """
  Normalized issue record used by orchestration.
  """

  defstruct id: nil,
            identifier: nil,
            title: nil,
            description: nil,
            priority: nil,
            state: nil,
            branch_name: nil,
            url: nil,
            labels: [],
            blocked_by: [],
            created_at: nil,
            updated_at: nil

  @type t :: %__MODULE__{}

  @spec normalize(t() | map()) :: t()
  def normalize(%__MODULE__{} = issue), do: %{issue | labels: normalize_labels(issue.labels)}

  def normalize(map) when is_map(map) do
    map
    |> struct(__MODULE__)
    |> normalize()
  end

  defp normalize_labels(labels) when is_list(labels),
    do: Enum.map(labels, &(to_string(&1) |> String.downcase()))

  defp normalize_labels(_labels), do: []
end
