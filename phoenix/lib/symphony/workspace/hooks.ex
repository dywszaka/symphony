defmodule Symphony.Workspace.Hooks do
  @moduledoc """
  Executes workspace lifecycle hooks.
  """

  require Logger

  @type hook_name :: :after_create | :before_run | :after_run | :before_remove

  @spec run(hook_name(), String.t() | nil, Path.t(), pos_integer()) :: :ok | {:error, term()}
  def run(_hook, script, _workspace, _timeout_ms) when is_nil(script), do: :ok

  def run(_hook, script, _workspace, _timeout_ms)
      when is_binary(script) and byte_size(script) == 0,
      do: :ok

  def run(hook, script, workspace, timeout_ms)
      when is_atom(hook) and is_binary(script) and is_binary(workspace) and is_integer(timeout_ms) do
    if String.trim(script) == "" do
      :ok
    else
      Logger.debug("Running workspace hook #{hook} cwd=#{workspace}")

      task =
        Task.async(fn ->
          System.cmd("sh", ["-lc", script], cd: workspace, stderr_to_stdout: true)
        end)

      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {_output, 0}} ->
          :ok

        {:ok, {output, status}} ->
          Logger.warning("Workspace hook #{hook} failed status=#{status}: #{String.trim(output)}")
          {:error, {:hook_failed, hook, status, output}}

        nil ->
          Logger.warning("Workspace hook #{hook} timed out after #{timeout_ms}ms")
          {:error, {:hook_timeout, hook, timeout_ms}}
      end
    end
  rescue
    error in ErlangError ->
      {:error, {:hook_exec_error, hook, Exception.message(error)}}
  end
end
