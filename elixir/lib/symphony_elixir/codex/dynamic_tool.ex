defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias SymphonyElixir.{Linear.Client, TaskTracker}

  @linear_graphql_tool "linear_graphql"
  @tasktracker_create_comment_tool "tasktracker_create_comment"
  @tasktracker_update_state_tool "tasktracker_update_state"
  @tasktracker_update_workpad_tool "tasktracker_update_workpad"
  @linear_graphql_description """
  Execute a raw GraphQL query or mutation against Linear using Symphony's configured auth.
  """
  @linear_graphql_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["query"],
    "properties" => %{
      "query" => %{
        "type" => "string",
        "description" => "GraphQL query or mutation document to execute against Linear."
      },
      "variables" => %{
        "type" => ["object", "null"],
        "description" => "Optional GraphQL variables object.",
        "additionalProperties" => true
      }
    }
  }
  @tasktracker_create_comment_description """
  Create a comment on a TaskTracker task using Symphony's configured tracker auth.
  """
  @tasktracker_update_state_description """
  Update a TaskTracker task state using Symphony's configured tracker auth.
  """
  @tasktracker_update_workpad_description """
  Replace or update a TaskTracker task workpad using Symphony's configured tracker auth.
  """
  @issue_id_property %{
    "type" => "string",
    "description" => "TaskTracker task id."
  }
  @body_property %{
    "type" => "string",
    "description" => "Text or markdown body to write."
  }
  @state_property %{
    "type" => "string",
    "description" => "Target TaskTracker state name."
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @linear_graphql_tool ->
        execute_linear_graphql(arguments, opts)

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
        "name" => @linear_graphql_tool,
        "description" => @linear_graphql_description,
        "inputSchema" => @linear_graphql_input_schema
      },
      %{
        "name" => @tasktracker_create_comment_tool,
        "description" => @tasktracker_create_comment_description,
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "body"], %{
            "issue_id" => @issue_id_property,
            "body" => @body_property
          })
      },
      %{
        "name" => @tasktracker_update_state_tool,
        "description" => @tasktracker_update_state_description,
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "state"], %{
            "issue_id" => @issue_id_property,
            "state" => @state_property
          })
      },
      %{
        "name" => @tasktracker_update_workpad_tool,
        "description" => @tasktracker_update_workpad_description,
        "inputSchema" =>
          tasktracker_input_schema(["issue_id", "body"], %{
            "issue_id" => @issue_id_property,
            "body" => @body_property
          })
      }
    ]
  end

  defp execute_linear_graphql(arguments, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_graphql_arguments(arguments),
         {:ok, response} <- linear_client.(query, variables, []) do
      graphql_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
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

  defp call_tracker(tracker, function, args) when is_atom(tracker) do
    apply(tracker, function, args)
  end

  defp call_tracker(tracker, function, args) when is_map(tracker) do
    case Map.get(tracker, function) || Map.get(tracker, Atom.to_string(function)) do
      fun when is_function(fun, length(args)) -> apply(fun, args)
      _ -> {:error, {:missing_tracker_function, function}}
    end
  end

  defp call_tracker(_tracker, function, _args), do: {:error, {:missing_tracker_function, function}}

  defp tasktracker_input_schema(required, properties) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => required,
      "properties" => properties
    }
  end

  defp normalize_linear_graphql_arguments(arguments) when is_binary(arguments) do
    case String.trim(arguments) do
      "" -> {:error, :missing_query}
      query -> {:ok, query, %{}}
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_map(arguments) do
    case normalize_query(arguments) do
      {:ok, query} ->
        case normalize_variables(arguments) do
          {:ok, variables} ->
            {:ok, query, variables}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_linear_graphql_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_query(arguments) do
    case Map.get(arguments, "query") || Map.get(arguments, :query) do
      query when is_binary(query) ->
        case String.trim(query) do
          "" -> {:error, :missing_query}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(arguments) do
    case Map.get(arguments, "variables") || Map.get(arguments, :variables) || %{} do
      variables when is_map(variables) -> {:ok, variables}
      _ -> {:error, :invalid_variables}
    end
  end

  defp graphql_response(response) do
    success =
      case response do
        %{"errors" => errors} when is_list(errors) and errors != [] -> false
        %{errors: errors} when is_list(errors) and errors != [] -> false
        _ -> true
      end

    dynamic_tool_response(success, encode_payload(response))
  end

  defp failure_response(payload) do
    dynamic_tool_response(false, encode_payload(payload))
  end

  defp dynamic_tool_response(success, output) when is_boolean(success) and is_binary(output) do
    %{
      "success" => success,
      "output" => output,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => output
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:missing_query) do
    %{
      "error" => %{
        "message" => "`linear_graphql` requires a non-empty `query` string."
      }
    }
  end

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`linear_graphql` expects either a GraphQL query string or an object with `query` and optional `variables`."
      }
    }
  end

  defp tool_error_payload(:invalid_variables) do
    %{
      "error" => %{
        "message" => "`linear_graphql.variables` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:missing_linear_api_token) do
    %{
      "error" => %{
        "message" => "Symphony is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."
      }
    }
  end

  defp tool_error_payload({:linear_api_status, status}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:linear_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Linear GraphQL tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tasktracker_argument_error_payload({:missing_required, tool_name, fields}) do
    %{
      "error" => %{
        "message" => "`#{tool_name}` requires non-empty string arguments: #{tasktracker_field_list(fields)}."
      }
    }
  end

  defp tasktracker_argument_error_payload({:invalid_type, tool_name, fields}) do
    %{
      "error" => %{
        "message" => "`#{tool_name}` expects a JSON object with string fields: #{tasktracker_field_list(fields)}."
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

  defp tasktracker_field_list(fields) do
    fields
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(", ")
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
