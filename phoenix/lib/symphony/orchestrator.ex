defmodule Symphony.Orchestrator do
  @moduledoc """
  Owns Symphony runtime scheduling state.
  """

  use GenServer

  alias Symphony.Orchestrator.State

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

  @impl true
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call(:snapshot, _from, %State{} = state) do
    {:reply, {:ok, State.snapshot(state)}, state}
  end
end
