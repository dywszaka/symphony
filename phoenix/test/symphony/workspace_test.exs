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

  test "runs after_create only for newly created workspaces" do
    root = temp_root!()
    marker = Path.join([root, "Team_1", "created.txt"])
    hooks = %{after_create: "echo created > #{shell_escape(marker)}", timeout_ms: 1_000}

    assert {:ok, %{created_now: true}} = Workspace.create_for_issue("Team 1", root, hooks)
    assert String.trim(File.read!(marker)) == "created"

    File.rm!(marker)
    assert {:ok, %{created_now: false}} = Workspace.create_for_issue("Team 1", root, hooks)
    refute File.exists?(marker)
  end

  test "after_create failure aborts new workspace creation" do
    root = temp_root!()

    assert {:error, {:hook_failed, :after_create, 9, _output}} =
             Workspace.create_for_issue("Team 2", root, %{
               after_create: "exit 9",
               timeout_ms: 1_000
             })

    refute File.exists?(Path.join(root, "Team_2"))
  end

  test "before_remove failure is ignored and workspace is deleted" do
    root = temp_root!()
    assert {:ok, %{path: path}} = Workspace.create_for_issue("Team 3", root)
    assert File.dir?(path)

    assert :ok =
             Workspace.remove_for_issue("Team 3", root, %{
               before_remove: "echo cleanup && exit 8",
               timeout_ms: 1_000
             })

    refute File.exists?(path)
  end

  defp temp_root! do
    Path.join(System.tmp_dir!(), "symphony-workspace-test-#{System.unique_integer([:positive])}")
  end

  defp shell_escape(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end
