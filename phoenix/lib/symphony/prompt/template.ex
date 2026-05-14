defmodule Symphony.Prompt.Template do
  @moduledoc """
  Strict prompt template renderer for workflow prompt bodies.
  """

  alias Symphony.Tracker.Issue

  @default_prompt "You are working on an issue from Linear."
  @interpolation ~r/({{\s*.*?\s*}})/

  @spec render(String.t(), Issue.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(template, %Issue{} = issue, opts \\ []) when is_binary(template) do
    template = if String.trim(template) == "", do: @default_prompt, else: template

    context = %{
      "issue" => issue_context(issue),
      "attempt" => Keyword.get(opts, :attempt)
    }

    Regex.split(@interpolation, template, include_captures: true, trim: false)
    |> render_parts(context, [])
  end

  defp render_parts([], _context, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp render_parts([<<"{{", _rest::binary>> = part | rest], context, acc) do
    expression =
      part
      |> String.trim_leading("{{")
      |> String.trim_trailing("}}")
      |> String.trim()

    case render_expression(expression, context) do
      {:ok, value} -> render_parts(rest, context, [value | acc])
      {:error, reason} -> {:error, {:template_render_error, reason}}
    end
  end

  defp render_parts([part | rest], context, acc), do: render_parts(rest, context, [part | acc])

  defp render_expression(expression, context) do
    case String.split(expression, "|", parts: 2) do
      [_path, filter] ->
        filter_name =
          filter
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> hd()

        {:error, {:unknown_filter, filter_name}}

      [path] ->
        resolve_path(String.trim(path), context)
    end
  end

  defp resolve_path("", _context), do: {:error, {:unknown_variable, ""}}

  defp resolve_path(path, context) do
    parts = String.split(path, ".")

    case do_resolve(parts, context) do
      {:ok, value} -> {:ok, render_value(value)}
      :error -> {:error, {:unknown_variable, path}}
    end
  end

  defp do_resolve([key], map) when is_map(map) do
    if Map.has_key?(map, key), do: {:ok, Map.fetch!(map, key)}, else: :error
  end

  defp do_resolve([key | rest], map) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> do_resolve(rest, value)
      :error -> :error
    end
  end

  defp do_resolve(_parts, _value), do: :error

  defp issue_context(%Issue{} = issue) do
    issue
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp render_value(nil), do: ""
  defp render_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp render_value(values) when is_list(values), do: Enum.map_join(values, ", ", &render_value/1)
  defp render_value(value) when is_map(value), do: Jason.encode!(value)
  defp render_value(value), do: to_string(value)
end
