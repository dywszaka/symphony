defmodule Symphony.Tracker.MemoryTest do
  use ExUnit.Case, async: false

  alias Symphony.Tracker.{Issue, Memory}

  setup do
    Memory.put_issues([])
    :ok
  end

  test "fetch_candidate_issues returns configured memory issues" do
    issue = %Issue{
      id: "1",
      identifier: "MT-1",
      title: "Build",
      state: "Todo",
      labels: ["Backend"]
    }

    Memory.put_issues([issue])

    assert {:ok, [%Issue{} = fetched]} = Memory.fetch_candidate_issues()
    assert fetched.identifier == "MT-1"
    assert fetched.labels == ["backend"]
  end

  test "fetch_issue_states_by_ids returns matching issues only" do
    Memory.put_issues([
      %Issue{id: "1", identifier: "MT-1", title: "One", state: "Todo"},
      %Issue{id: "2", identifier: "MT-2", title: "Two", state: "Done"}
    ])

    assert {:ok, [%Issue{id: "2"}]} = Memory.fetch_issue_states_by_ids(["2"])
  end
end
