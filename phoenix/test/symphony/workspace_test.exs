defmodule Symphony.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Symphony.Workspace

  test "sanitizes workspace keys according to the spec" do
    assert Workspace.workspace_key("ABC-123") == "ABC-123"
    assert Workspace.workspace_key("Team 1/ABC:123") == "Team_1_ABC_123"
  end

  test "creates and reuses per-issue workspace directories under root" do
    root = temp_root!()

    assert {:ok, %{path: path, workspace_key: "Team_1", created_now: true}} =
             Workspace.create_for_issue("Team 1", root)

    assert File.dir?(path)
    assert String.starts_with?(path, Path.expand(root) <> "/")

    assert {:ok, %{path: ^path, created_now: false}} = Workspace.create_for_issue("Team 1", root)
  end

  defp temp_root! do
    Path.join(System.tmp_dir!(), "symphony-workspace-test-#{System.unique_integer([:positive])}")
  end
end
