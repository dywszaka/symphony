defmodule Symphony.Workflow.Watcher do
  @moduledoc """
  Polls a workflow file and applies valid reloads to an orchestrator.
  """

  use GenServer

  alias Symphony.Config.Settings
  alias Symphony.Orchestrator
  alias Symphony.Workflow.Loader

  defstruct workflow_path: nil,
            orchestrator: Orchestrator,
            poll_interval_ms: 1_000,
            last_mtime: nil,
            settings: nil,
            prompt_template: nil,
            last_error: nil,
            timer_ref: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec reload_now(GenServer.server()) :: :ok
  def reload_now(server), do: GenServer.call(server, :reload_now)

  @spec snapshot(GenServer.server()) :: {:ok, map()}
  def snapshot(server), do: GenServer.call(server, :snapshot)

  @impl true
  def init(opts) do
    state = %__MODULE__{
      workflow_path: Keyword.fetch!(opts, :workflow_path),
      orchestrator: Keyword.fetch!(opts, :orchestrator),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 1_000)
    }

    state = reload(state)
    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_call(:reload_now, _from, state) do
    {:reply, :ok, reload(state)}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, snapshot_state(state)}, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state =
      if changed?(state) do
        reload(state)
      else
        state
      end

    {:noreply, schedule_poll(state)}
  end

  defp reload(state) do
    case load_settings(state.workflow_path) do
      {:ok, settings, prompt_template} ->
        :ok = Orchestrator.reconfigure(state.orchestrator, settings, prompt_template)

        %{
          state
          | settings: settings,
            prompt_template: prompt_template,
            last_error: nil,
            last_mtime: mtime(state.workflow_path)
        }

      {:error, reason} ->
        %{state | last_error: reason, last_mtime: mtime(state.workflow_path)}
    end
  end

  defp load_settings(workflow_path) do
    with {:ok, workflow} <- Loader.load(workflow_path),
         {:ok, settings} <- Settings.from_workflow(workflow, workflow_path),
         :ok <- Settings.validate_dispatch(settings) do
      {:ok, settings, workflow.prompt_template}
    end
  end

  defp changed?(state), do: mtime(state.workflow_path) != state.last_mtime

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      {:error, _reason} -> nil
    end
  end

  defp schedule_poll(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: Process.send_after(self(), :poll, state.poll_interval_ms)}
  end

  defp snapshot_state(state) do
    %{
      workflow_path: state.workflow_path,
      last_mtime: state.last_mtime,
      settings: state.settings,
      prompt_template: state.prompt_template,
      last_error: state.last_error
    }
  end
end
