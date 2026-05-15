defmodule Symphony.Orchestrator do
  @moduledoc """
  Owns Symphony runtime scheduling state.
  """

  use GenServer

  alias Symphony.Orchestrator.{Scheduling, State}
  alias Symphony.Workspace

  @default_settings %{
    tracker: %{
      active_states: ["Todo", "In Progress"],
      terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    },
    polling: %{
      interval_ms: 30_000
    },
    agent: %{
      max_concurrent_agents: 10,
      max_retry_backoff_ms: 300_000,
      max_concurrent_agents_by_state: %{}
    },
    codex: %{
      stall_timeout_ms: 300_000
    }
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, :unavailable}
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec dispatch_once(GenServer.server()) :: :ok
  def dispatch_once(server \\ __MODULE__) do
    GenServer.call(server, :dispatch_once)
  end

  @spec reconcile_once(GenServer.server()) :: :ok
  def reconcile_once(server \\ __MODULE__) do
    GenServer.call(server, :reconcile_once)
  end

  @spec retry_now(GenServer.server(), String.t()) :: :ok
  def retry_now(server \\ __MODULE__, issue_id) when is_binary(issue_id) do
    GenServer.call(server, {:retry_now, issue_id})
  end

  @spec reconfigure(GenServer.server(), map(), String.t()) :: :ok
  def reconfigure(server \\ __MODULE__, settings, prompt_template)
      when is_map(settings) and is_binary(prompt_template) do
    GenServer.call(server, {:reconfigure, settings, prompt_template})
  end

  @impl true
  def init(opts) do
    settings = Keyword.get(opts, :settings, @default_settings)

    state = %State{
      tracker: Keyword.get(opts, :tracker, Symphony.Tracker.Memory),
      runner: Keyword.get(opts, :runner),
      runner_opts: Keyword.get(opts, :runner_opts, []),
      settings: settings,
      auto_poll: Keyword.get(opts, :auto_poll, false),
      max_concurrent_agents: settings.agent.max_concurrent_agents,
      poll_interval_ms: settings.polling.interval_ms,
      continuation_retry_delay_ms: Keyword.get(opts, :continuation_retry_delay_ms, 1_000),
      failure_retry_base_ms: Keyword.get(opts, :failure_retry_base_ms, 10_000)
    }

    startup_terminal_workspace_cleanup(state)
    {:ok, maybe_schedule_poll(state, 0)}
  end

  @impl true
  def handle_call(:snapshot, _from, %State{} = state) do
    {:reply, {:ok, State.snapshot(state)}, state}
  end

  def handle_call(:dispatch_once, _from, %State{} = state) do
    {:reply, :ok, dispatch_candidates(state)}
  end

  def handle_call(:reconcile_once, _from, %State{} = state) do
    {:reply, :ok, reconcile_running(state)}
  end

  def handle_call({:retry_now, issue_id}, _from, %State{} = state) do
    {:reply, :ok, handle_retry(state, issue_id)}
  end

  def handle_call({:reconfigure, settings, prompt_template}, _from, %State{} = state) do
    state = apply_reconfigure(state, settings, prompt_template)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, %State{} = state) do
    case running_issue_for_monitor(state.running, monitor_ref) do
      {issue_id, running_entry} ->
        state =
          state
          |> remove_running(issue_id)
          |> handle_worker_exit(issue_id, running_entry, reason)

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:retry_issue, issue_id}, %State{} = state) do
    {:noreply, handle_retry(state, issue_id)}
  end

  def handle_info({:codex_update, issue_id, message}, %State{} = state) do
    {:noreply, handle_codex_update(state, issue_id, message)}
  end

  def handle_info(:poll, %State{} = state) do
    state =
      state
      |> reconcile_running()
      |> dispatch_candidates()
      |> maybe_schedule_poll(state.poll_interval_ms)

    {:noreply, state}
  end

  defp dispatch_candidates(%State{} = state) do
    case state.tracker.fetch_candidate_issues() do
      {:ok, issues} ->
        issues
        |> Scheduling.sort_issues()
        |> Enum.reduce(state, &maybe_dispatch_issue(&2, &1, nil))

      {:error, _reason} ->
        state
    end
  end

  defp apply_reconfigure(%State{} = state, settings, prompt_template) do
    %{
      state
      | settings: settings,
        max_concurrent_agents: settings.agent.max_concurrent_agents,
        poll_interval_ms: settings.polling.interval_ms,
        runner_opts: Keyword.put(state.runner_opts, :prompt_template, prompt_template)
    }
  end

  defp maybe_dispatch_issue(%State{} = state, issue, attempt) do
    if Scheduling.dispatch_eligible?(issue, active_states(state), terminal_states(state),
         claimed: state.claimed,
         running: state.running,
         max_concurrent_agents: state.max_concurrent_agents,
         max_concurrent_agents_by_state: state.settings.agent.max_concurrent_agents_by_state
       ) do
      dispatch_issue(state, issue, attempt)
    else
      state
    end
  end

  defp dispatch_issue(%State{} = state, issue, attempt) do
    runner = state.runner || Symphony.SupportMissingRunner
    orchestrator = self()

    runner_opts =
      state.runner_opts
      |> Keyword.put(:attempt, attempt)
      |> Keyword.put_new(:settings, state.settings)
      |> Keyword.put(:on_message, fn message ->
        send(orchestrator, {:codex_update, issue.id, message})
      end)

    case runner.start_issue(issue, runner_opts) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)

        running_entry = %{
          issue: issue,
          identifier: issue.identifier,
          state: issue.state,
          pid: pid,
          monitor_ref: monitor_ref,
          started_at_ms: now_ms(),
          attempt: attempt,
          session_id: nil,
          last_codex_event: nil,
          last_codex_timestamp_ms: nil,
          codex_input_tokens: 0,
          codex_output_tokens: 0,
          codex_total_tokens: 0,
          last_reported_input_tokens: 0,
          last_reported_output_tokens: 0,
          last_reported_total_tokens: 0
        }

        %{
          state
          | claimed: MapSet.put(state.claimed, issue.id),
            running: Map.put(state.running, issue.id, running_entry)
        }

      {:error, reason} ->
        schedule_retry(
          state,
          issue.id,
          1,
          issue.identifier,
          inspect(reason),
          state.failure_retry_base_ms
        )
    end
  end

  defp handle_worker_exit(state, issue_id, running_entry, :normal) do
    state
    |> Map.update!(:completed, &MapSet.put(&1, issue_id))
    |> schedule_retry(
      issue_id,
      1,
      running_entry.identifier,
      nil,
      state.continuation_retry_delay_ms
    )
  end

  defp handle_worker_exit(state, issue_id, running_entry, reason) do
    attempt = (running_entry.attempt || 0) + 1
    delay = failure_delay_ms(state, attempt)

    schedule_retry(
      state,
      issue_id,
      attempt,
      running_entry.identifier,
      "agent exited: #{inspect(reason)}",
      delay
    )
  end

  defp schedule_retry(state, issue_id, attempt, identifier, error, delay_ms) do
    old_entry = Map.get(state.retry_attempts, issue_id)
    if old_entry && old_entry.timer_ref, do: Process.cancel_timer(old_entry.timer_ref)

    timer_ref = Process.send_after(self(), {:retry_issue, issue_id}, delay_ms)

    retry_entry = %{
      issue_id: issue_id,
      identifier: identifier,
      attempt: attempt,
      due_at_ms: now_ms() + delay_ms,
      timer_ref: timer_ref,
      error: error
    }

    %{
      state
      | claimed: MapSet.put(state.claimed, issue_id),
        retry_attempts: Map.put(state.retry_attempts, issue_id, retry_entry)
    }
  end

  defp handle_retry(%State{} = state, issue_id) do
    case Map.pop(state.retry_attempts, issue_id) do
      {nil, _retry_attempts} ->
        state

      {retry_entry, retry_attempts} ->
        if retry_entry.timer_ref, do: Process.cancel_timer(retry_entry.timer_ref)

        state = %{
          state
          | retry_attempts: retry_attempts,
            claimed: MapSet.delete(state.claimed, issue_id)
        }

        case state.tracker.fetch_candidate_issues() do
          {:ok, issues} ->
            case Enum.find(issues, &(&1.id == issue_id)) do
              nil -> release_claim(state, issue_id)
              issue -> maybe_dispatch_issue(state, issue, retry_entry.attempt)
            end

          {:error, reason} ->
            schedule_retry(
              state,
              issue_id,
              retry_entry.attempt,
              retry_entry.identifier,
              inspect(reason),
              failure_delay_ms(state, retry_entry.attempt)
            )
        end
    end
  end

  defp reconcile_running(%State{running: running} = state) when map_size(running) == 0, do: state

  defp reconcile_running(%State{} = state) do
    state = reconcile_stalled_runs(state)
    issue_ids = Map.keys(state.running)

    if issue_ids == [] do
      state
    else
      case state.tracker.fetch_issue_states_by_ids(issue_ids) do
        {:ok, issues} ->
          issue_by_id = Map.new(issues, &{&1.id, &1})

          Enum.reduce(issue_ids, state, fn issue_id, state_acc ->
            reconcile_issue_state(state_acc, issue_id, Map.get(issue_by_id, issue_id))
          end)

        {:error, _reason} ->
          state
      end
    end
  end

  defp handle_codex_update(%State{} = state, issue_id, message) do
    case Map.fetch(state.running, issue_id) do
      {:ok, entry} ->
        {entry, state} =
          entry
          |> put_codex_event(message)
          |> maybe_put_session_id(message)
          |> apply_token_usage_delta(state, message)

        state
        |> put_in([Access.key!(:running), issue_id], entry)
        |> maybe_put_rate_limits(message)

      :error ->
        state
    end
  end

  defp put_codex_event(entry, message) do
    %{
      entry
      | last_codex_event: message |> Map.get(:event) |> event_to_string(),
        last_codex_timestamp_ms: now_ms()
    }
  end

  defp maybe_put_session_id(entry, message) do
    payload = Map.get(message, :payload, %{})
    thread_id = payload["threadId"]
    turn_id = payload["turnId"] || get_in(payload, ["turn", "id"])

    if is_binary(thread_id) and is_binary(turn_id) do
      %{entry | session_id: "#{thread_id}-#{turn_id}"}
    else
      entry
    end
  end

  defp apply_token_usage_delta(entry, state, message) do
    case extract_total_usage(Map.get(message, :payload, %{})) do
      nil ->
        {entry, state}

      usage ->
        input_delta = max(usage.input_tokens - entry.last_reported_input_tokens, 0)
        output_delta = max(usage.output_tokens - entry.last_reported_output_tokens, 0)
        total_delta = max(usage.total_tokens - entry.last_reported_total_tokens, 0)

        entry = %{
          entry
          | codex_input_tokens: usage.input_tokens,
            codex_output_tokens: usage.output_tokens,
            codex_total_tokens: usage.total_tokens,
            last_reported_input_tokens: usage.input_tokens,
            last_reported_output_tokens: usage.output_tokens,
            last_reported_total_tokens: usage.total_tokens
        }

        state = %{
          state
          | codex_totals: %{
              input_tokens: state.codex_totals.input_tokens + input_delta,
              output_tokens: state.codex_totals.output_tokens + output_delta,
              total_tokens: state.codex_totals.total_tokens + total_delta,
              seconds_running: state.codex_totals.seconds_running
            }
        }

        {entry, state}
    end
  end

  defp extract_total_usage(%{"tokenUsage" => %{"total" => total}}) when is_map(total) do
    %{
      input_tokens:
        integer_value(total, ["inputTokens", "input_tokens", :inputTokens, :input_tokens]),
      output_tokens:
        integer_value(total, ["outputTokens", "output_tokens", :outputTokens, :output_tokens]),
      total_tokens:
        integer_value(total, ["totalTokens", "total_tokens", :totalTokens, :total_tokens])
    }
  end

  defp extract_total_usage(_payload), do: nil

  defp maybe_put_rate_limits(state, %{event: :account_rate_limits_updated, payload: payload}) do
    %{state | codex_rate_limits: Map.get(payload, "rateLimits", payload)}
  end

  defp maybe_put_rate_limits(state, _message), do: state

  defp reconcile_stalled_runs(%State{} = state) do
    timeout_ms = get_in(state.settings, [:codex, :stall_timeout_ms]) || 0

    if timeout_ms <= 0 do
      state
    else
      Enum.reduce(state.running, state, fn {issue_id, entry}, state_acc ->
        last_activity_ms = entry.last_codex_timestamp_ms || entry.started_at_ms

        if now_ms() - last_activity_ms > timeout_ms do
          stall_running(state_acc, issue_id, entry)
        else
          state_acc
        end
      end)
    end
  end

  defp stall_running(state, issue_id, entry) do
    Process.demonitor(entry.monitor_ref, [:flush])
    if Process.alive?(entry.pid), do: Process.exit(entry.pid, :kill)
    attempt = (entry.attempt || 0) + 1

    state
    |> remove_running(issue_id)
    |> schedule_retry(
      issue_id,
      attempt,
      entry.identifier,
      "codex session stalled",
      failure_delay_ms(state, attempt)
    )
  end

  defp integer_value(map, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(map, key) do
        value when is_integer(value) -> value
        _ -> nil
      end
    end)
  end

  defp event_to_string(nil), do: nil
  defp event_to_string(event) when is_atom(event), do: Atom.to_string(event)
  defp event_to_string(event), do: to_string(event)

  defp reconcile_issue_state(state, issue_id, nil), do: release_running(state, issue_id)

  defp reconcile_issue_state(state, issue_id, issue) do
    cond do
      Scheduling.terminal_state?(issue.state, terminal_states(state)) ->
        release_running(state, issue_id)

      Scheduling.active_state?(issue.state, active_states(state)) ->
        put_in(state.running[issue_id].issue, issue)
        |> put_in([Access.key!(:running), issue_id, :state], issue.state)
        |> put_in([Access.key!(:running), issue_id, :identifier], issue.identifier)

      true ->
        release_running(state, issue_id)
    end
  end

  defp release_running(%State{} = state, issue_id) do
    case Map.get(state.running, issue_id) do
      nil ->
        release_claim(state, issue_id)

      running_entry ->
        Process.demonitor(running_entry.monitor_ref, [:flush])
        if Process.alive?(running_entry.pid), do: Process.exit(running_entry.pid, :kill)

        state
        |> remove_running(issue_id)
        |> release_claim(issue_id)
    end
  end

  defp remove_running(state, issue_id),
    do: %{state | running: Map.delete(state.running, issue_id)}

  defp release_claim(state, issue_id),
    do: %{state | claimed: MapSet.delete(state.claimed, issue_id)}

  defp running_issue_for_monitor(running, monitor_ref) do
    Enum.find(running, fn {_issue_id, entry} -> entry.monitor_ref == monitor_ref end)
  end

  defp active_states(state), do: state.settings.tracker.active_states
  defp terminal_states(state), do: state.settings.tracker.terminal_states
  defp now_ms, do: System.monotonic_time(:millisecond)

  defp failure_delay_ms(state, attempt) do
    min(
      state.failure_retry_base_ms * Integer.pow(2, attempt - 1),
      state.settings.agent.max_retry_backoff_ms
    )
  end

  defp maybe_schedule_poll(%State{auto_poll: false} = state, _delay_ms), do: state

  defp maybe_schedule_poll(%State{auto_poll: true} = state, delay_ms) do
    timer_ref = Process.send_after(self(), :poll, delay_ms)
    %{state | poll_timer_ref: timer_ref}
  end

  defp startup_terminal_workspace_cleanup(%State{} = state) do
    with %{workspace: %{root: root}, hooks: hooks} <- state.settings,
         {:ok, issues} <- state.tracker.fetch_issues_by_states(terminal_states(state)) do
      Enum.each(issues, fn issue ->
        if is_binary(issue.identifier) do
          Workspace.remove_for_issue(issue.identifier, root, hooks)
        end
      end)
    else
      _reason -> :ok
    end

    :ok
  end
end
