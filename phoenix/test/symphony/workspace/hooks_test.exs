defmodule Symphony.Workspace.HooksTest do
  use ExUnit.Case, async: true

  alias Symphony.Workspace.Hooks

  test "runs hook scripts in the workspace cwd" do
    workspace = temp_dir!()
    marker = Path.join(workspace, "pwd.txt")

    assert :ok = Hooks.run(:before_run, "pwd > #{shell_escape(marker)}", workspace, 1_000)
    assert String.trim(File.read!(marker)) == workspace
  end

  test "maps non-zero exits" do
    workspace = temp_dir!()

    assert {:error, {:hook_failed, :before_run, 7, output}} =
             Hooks.run(:before_run, "echo nope && exit 7", workspace, 1_000)

    assert output =~ "nope"
  end

  test "maps timeouts" do
    workspace = temp_dir!()

    assert {:error, {:hook_timeout, :before_run, 20}} =
             Hooks.run(:before_run, "sleep 1", workspace, 20)
  end

  test "blank hooks are no-ops" do
    workspace = temp_dir!()

    assert :ok = Hooks.run(:after_run, nil, workspace, 1_000)
    assert :ok = Hooks.run(:after_run, "  ", workspace, 1_000)
  end

  defp temp_dir! do
    path = Path.join(System.tmp_dir!(), "symphony-hooks-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp shell_escape(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end
