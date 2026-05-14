defmodule Symphony.Codex.AppServer do
  @moduledoc """
  Minimal Codex app-server JSON-RPC client over stdio.
  """

  alias Symphony.Tracker.Issue

  defstruct [:port, :thread_id, :workspace, :settings]

  @type t :: %__MODULE__{}

  @initialize_id 1
  @thread_start_id 2
  @turn_start_id 3

  @spec start_session(Path.t(), map()) :: {:ok, t()} | {:error, term()}
  def start_session(workspace, settings) when is_binary(workspace) do
    command = settings.codex.command

    with {:ok, port} <- open_port(command, workspace),
         :ok <- initialize(port, settings),
         {:ok, thread_id} <- start_thread(port, workspace, settings) do
      {:ok,
       %__MODULE__{port: port, thread_id: thread_id, workspace: workspace, settings: settings}}
    else
      {:error, reason, port} ->
        close_port(port)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_turn(t(), String.t(), Issue.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(%__MODULE__{} = session, prompt, %Issue{} = _issue, opts \\ [])
      when is_binary(prompt) do
    on_message = Keyword.get(opts, :on_message, fn _message -> :ok end)

    with {:ok, turn_id} <- start_turn(session, prompt, on_message),
         {:ok, result} <- await_turn_completion(session, turn_id, on_message) do
      {:ok, result}
    end
  end

  @spec stop_session(t()) :: :ok
  def stop_session(%__MODULE__{port: port}), do: close_port(port)

  defp open_port(command, workspace) do
    shell = System.find_executable("bash") || System.find_executable("sh")

    if is_nil(shell) do
      {:error, :codex_shell_not_found}
    else
      port =
        Port.open({:spawn_executable, shell}, [
          :binary,
          :exit_status,
          {:args, ["-lc", command]},
          {:cd, workspace},
          {:line, 1_000_000}
        ])

      {:ok, port}
    end
  rescue
    error in ArgumentError -> {:error, {:codex_launch_failed, Exception.message(error)}}
  end

  defp initialize(port, settings) do
    request = %{
      "id" => @initialize_id,
      "method" => "initialize",
      "params" => %{
        "clientInfo" => %{"name" => "symphony", "title" => "Symphony", "version" => "0.1.0"},
        "capabilities" => %{"experimentalApi" => true}
      }
    }

    with :ok <- write_json(port, request),
         {:ok, _result} <-
           await_response(port, @initialize_id, settings.codex.read_timeout_ms, nil) do
      :ok
    else
      {:error, reason} -> {:error, reason, port}
    end
  end

  defp start_thread(port, workspace, settings) do
    params =
      compact_nil(%{
        "cwd" => workspace,
        "approvalPolicy" => settings.codex.approval_policy,
        "sandbox" => settings.codex.thread_sandbox,
        "ephemeral" => true,
        "serviceName" => "symphony",
        "sessionStartSource" => "local"
      })

    request = %{"id" => @thread_start_id, "method" => "thread/start", "params" => params}

    with :ok <- write_json(port, request),
         {:ok, result} <-
           await_response(port, @thread_start_id, settings.codex.read_timeout_ms, nil),
         {:ok, thread_id} <- extract_thread_id(result) do
      {:ok, thread_id}
    else
      {:error, reason} -> {:error, reason, port}
    end
  end

  defp start_turn(%__MODULE__{} = session, prompt, on_message) do
    params =
      compact_nil(%{
        "threadId" => session.thread_id,
        "cwd" => session.workspace,
        "input" => [%{"type" => "text", "text" => prompt}],
        "approvalPolicy" => session.settings.codex.approval_policy,
        "sandboxPolicy" => session.settings.codex.turn_sandbox_policy
      })

    request = %{"id" => @turn_start_id, "method" => "turn/start", "params" => params}

    with :ok <- write_json(session.port, request),
         {:ok, result} <-
           await_response(
             session.port,
             @turn_start_id,
             session.settings.codex.read_timeout_ms,
             on_message
           ),
         {:ok, turn_id} <- extract_turn_id(result) do
      {:ok, turn_id}
    end
  end

  defp await_turn_completion(%__MODULE__{} = session, turn_id, on_message) do
    deadline_ms = System.monotonic_time(:millisecond) + session.settings.codex.turn_timeout_ms
    do_await_turn_completion(session, turn_id, on_message, deadline_ms)
  end

  defp do_await_turn_completion(%__MODULE__{} = session, turn_id, on_message, deadline_ms) do
    case read_loop(session.port, remaining_timeout_ms(deadline_ms), on_message) do
      {:notification, "turn/completed", params} ->
        {:ok, %{thread_id: session.thread_id, turn_id: turn_id, payload: params}}

      {:notification, method, params} when method in ["turn/failed", "turn/cancelled"] ->
        {:error, {method_error(method), params}}

      {:notification, _method, _params} ->
        do_await_turn_completion(session, turn_id, on_message, deadline_ms)

      {:server_request, request} ->
        case handle_server_request(session.port, request) do
          :ok -> do_await_turn_completion(session, turn_id, on_message, deadline_ms)
          {:error, reason} -> {:error, reason}
        end

      {:error, :codex_read_timeout} ->
        {:error, :codex_turn_timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_response(port, id, timeout_ms, on_message) do
    case read_loop(port, timeout_ms, on_message) do
      {:response, ^id, %{"result" => result}} ->
        {:ok, result}

      {:response, ^id, %{"error" => error}} ->
        {:error, {:codex_rpc_error, error}}

      {:response, _other_id, _payload} ->
        await_response(port, id, timeout_ms, on_message)

      {:notification, _method, _params} ->
        await_response(port, id, timeout_ms, on_message)

      {:server_request, request} ->
        case handle_server_request(port, request) do
          :ok -> await_response(port, id, timeout_ms, on_message)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_loop(port, timeout_ms, on_message) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        decode_line(line, on_message)

      {^port, {:data, {:noeol, line}}} ->
        decode_line(line, on_message)

      {^port, {:exit_status, status}} ->
        {:error, {:codex_app_server_exit, status}}
    after
      timeout_ms -> {:error, :codex_read_timeout}
    end
  end

  defp decode_line(line, on_message) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{"id" => _id, "method" => _method} = request} ->
        {:server_request, request}

      {:ok, %{"id" => id} = response} when not is_nil(id) ->
        {:response, id, response}

      {:ok, %{"method" => method} = notification} ->
        params = Map.get(notification, "params", %{})
        emit_notification(on_message, method, params, notification)
        {:notification, method, params}

      {:ok, payload} ->
        {:error, {:codex_unknown_payload, payload}}

      {:error, _reason} ->
        {:error, {:codex_malformed_json, line}}
    end
  end

  defp decode_line(line, on_message), do: decode_line(to_string(line), on_message)

  defp handle_server_request(port, %{"id" => id, "method" => method, "params" => params}) do
    case method do
      "item/commandExecution/requestApproval" ->
        write_json(port, %{"id" => id, "result" => %{"decision" => "acceptForSession"}})

      "item/fileChange/requestApproval" ->
        write_json(port, %{"id" => id, "result" => %{"decision" => "acceptForSession"}})

      "item/tool/call" ->
        write_json(port, %{
          "id" => id,
          "result" => %{
            "success" => false,
            "contentItems" => [
              %{"type" => "inputText", "text" => "Unsupported Symphony client-side tool"}
            ]
          }
        })

      "item/tool/requestUserInput" ->
        {:error, {:turn_input_required, params}}

      "mcpServer/elicitation/request" ->
        {:error, {:turn_input_required, params}}

      _ ->
        write_json(port, %{
          "id" => id,
          "error" => %{"code" => -32601, "message" => "Unsupported server request: #{method}"}
        })
    end
  end

  defp handle_server_request(_port, request),
    do: {:error, {:codex_unknown_server_request, request}}

  defp emit_notification(nil, _method, _params, _payload), do: :ok

  defp emit_notification(on_message, method, params, payload) when is_function(on_message, 1) do
    event =
      method
      |> String.replace("/", "_")
      |> Macro.underscore()
      |> String.to_atom()

    on_message.(%{event: event, method: method, payload: params, raw: payload})
  end

  defp write_json(port, payload) do
    if Port.command(port, [Jason.encode!(payload), "\n"]),
      do: :ok,
      else: {:error, :codex_port_closed}
  rescue
    error in ArgumentError -> {:error, {:codex_write_failed, Exception.message(error)}}
  end

  defp extract_thread_id(%{"thread" => %{"id" => id}}) when is_binary(id), do: {:ok, id}
  defp extract_thread_id(result), do: {:error, {:codex_missing_thread_id, result}}

  defp extract_turn_id(%{"turn" => %{"id" => id}}) when is_binary(id), do: {:ok, id}
  defp extract_turn_id(result), do: {:error, {:codex_missing_turn_id, result}}

  defp method_error("turn/failed"), do: :turn_failed
  defp method_error("turn/cancelled"), do: :turn_cancelled

  defp compact_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp remaining_timeout_ms(deadline_ms) do
    max(deadline_ms - System.monotonic_time(:millisecond), 0)
  end

  defp close_port(port) when is_port(port) do
    Port.close(port)
    :ok
  catch
    :error, _reason -> :ok
  end
end
