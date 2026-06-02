defmodule Symphony.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias Symphony.TaskTracker

  @tasktracker_create_comment_tool "tasktracker_create_comment"
  @tasktracker_update_state_tool "tasktracker_update_state"
  @tasktracker_update_workpad_tool "tasktracker_update_workpad"

  @issue_id_property %{"type" => "string", "description" => "TaskTracker task id."}
  @body_property %{"type" => "string", "description" => "Text or markdown body to write."}
  @state_property %{"type" => "string", "description" => "Target TaskTracker state name."}

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @tasktracker_create_comment_tool ->
        execute_tasktracker_write(
          @tasktracker_create_comment_tool,
          arguments,
          [:issue_id, :body],
          opts,
          &call_tracker(&1, :create_comment, [&2, &3])
        )

      @tasktracker_update_state_tool ->
        execute_tasktracker_write(
          @tasktracker_update_state_tool,
          arguments,
          [:issue_id, :state],
          opts,
          &call_tracker(&1, :update_issue_state, [&2, &3])
        )

      @tasktracker_update_workpad_tool ->
        execute_tasktracker_write(
          @tasktracker_update_workpad_tool,
          arguments,
          [:issue_id, :body],
          opts,
          &call_tracker(&1, :update_workpad, [&2, &3])
        )

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        "name" => @tasktracker_create_comment_tool,
        "description" => "Create a comment on a TaskTracker task.",
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "body"], %{
            "issue_id" => @issue_id_property,
            "body" => @body_property
          })
      },
      %{
        "name" => @tasktracker_update_state_tool,
        "description" => "Update a TaskTracker task state.",
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "state"], %{
            "issue_id" => @issue_id_property,
            "state" => @state_property
          })
      },
      %{
        "name" => @tasktracker_update_workpad_tool,
        "description" => "Replace or update a TaskTracker task workpad.",
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "body"], %{
            "issue_id" => @issue_id_property,
            "body" => @body_property
          })
      }
    ]
  end

  defp execute_tasktracker_write(tool_name, arguments, fields, opts, callback) do
    tracker = Keyword.get(opts, :tracker, TaskTracker.Adapter)

    with {:ok, values} <- normalize_tasktracker_arguments(tool_name, arguments, fields),
         :ok <- callback.(tracker, values.issue_id, values.value) do
      dynamic_tool_response(true, encode_payload(%{"ok" => true}))
    else
      {:error, {:invalid_tasktracker_arguments, reason}} ->
        failure_response(tasktracker_argument_error_payload(reason))

      {:error, reason} ->
        failure_response(tasktracker_tool_error_payload(reason))
    end
  end

  defp normalize_tasktracker_arguments(tool_name, arguments, fields) when is_map(arguments) do
    case Enum.reduce_while(fields, {:ok, %{}}, &collect_tasktracker_field(arguments, &1, &2)) do
      {:ok, values} ->
        [primary_field, value_field] = fields

        {:ok,
         %{
           issue_id: Map.fetch!(values, primary_field),
           value: Map.fetch!(values, value_field)
         }}

      {:error, :missing_required} ->
        {:error, {:invalid_tasktracker_arguments, {:missing_required, tool_name, fields}}}
    end
  end

  defp normalize_tasktracker_arguments(tool_name, _arguments, fields),
    do: {:error, {:invalid_tasktracker_arguments, {:invalid_type, tool_name, fields}}}

  defp collect_tasktracker_field(arguments, field, {:ok, acc}) do
    key = Atom.to_string(field)

    case Map.get(arguments, key) || Map.get(arguments, field) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:halt, {:error, :missing_required}}
        else
          {:cont, {:ok, Map.put(acc, field, trimmed)}}
        end

      _ ->
        {:halt, {:error, :missing_required}}
    end
  end

  defp call_tracker(tracker, function, args) when is_atom(tracker),
    do: apply(tracker, function, args)

  defp call_tracker(tracker, function, args) when is_map(tracker) do
    case Map.get(tracker, function) || Map.get(tracker, Atom.to_string(function)) do
      fun when is_function(fun, length(args)) -> apply(fun, args)
      _ -> {:error, {:missing_tracker_function, function}}
    end
  end

  defp call_tracker(_tracker, function, _args),
    do: {:error, {:missing_tracker_function, function}}

  defp tasktracker_input_schema(required, properties) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => required,
      "properties" => properties
    }
  end

  defp tasktracker_argument_error_payload({:missing_required, tool_name, fields}) do
    %{
      "error" => %{
        "message" =>
          "`#{tool_name}` requires non-empty string arguments: #{tasktracker_field_list(fields)}."
      }
    }
  end

  defp tasktracker_argument_error_payload({:invalid_type, tool_name, fields}) do
    %{
      "error" => %{
        "message" =>
          "`#{tool_name}` expects a JSON object with string fields: #{tasktracker_field_list(fields)}."
      }
    }
  end

  defp tasktracker_tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "TaskTracker tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp failure_response(payload), do: dynamic_tool_response(false, encode_payload(payload))

  defp dynamic_tool_response(success, output) when is_boolean(success) and is_binary(output) do
    %{
      "success" => success,
      "output" => output,
      "contentItems" => [
        %{"type" => "inputText", "text" => output}
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload),
    do: Jason.encode!(payload, pretty: true)

  defp encode_payload(payload), do: inspect(payload)

  defp tasktracker_field_list(fields),
    do: fields |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")

  defp supported_tool_names, do: Enum.map(tool_specs(), & &1["name"])
end
