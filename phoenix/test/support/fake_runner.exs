defmodule Symphony.Support.FakeRunner do
  @behaviour Symphony.Runner.Behaviour

  @impl true
  def start_issue(issue, opts) do
    recipient = Keyword.get(opts, :recipient, self())

    pid =
      spawn(fn ->
        send(recipient, {:fake_runner_started, self(), issue})

        receive do
          :finish -> :ok
          {:crash, reason} -> exit(reason)
          :stop -> exit(:killed)
        end
      end)

    {:ok, pid}
  end
end
