defmodule Symphony.Workspace do
  @moduledoc """
  Creates isolated per-issue workspaces.
  """

  @type workspace :: %{
          path: Path.t(),
          workspace_key: String.t(),
          created_now: boolean()
        }

  @spec workspace_key(String.t() | nil) :: String.t()
  def workspace_key(nil), do: "issue"

  def workspace_key(identifier) when is_binary(identifier) do
    String.replace(identifier, ~r/[^A-Za-z0-9._-]/, "_")
  end

  @spec path_for_issue(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def path_for_issue(identifier, root) when is_binary(root) do
    key = workspace_key(identifier)
    root_path = Path.expand(root)
    workspace_path = Path.expand(Path.join(root_path, key))

    if inside_root?(workspace_path, root_path) do
      {:ok, workspace_path}
    else
      {:error, {:workspace_outside_root, workspace_path, root_path}}
    end
  end

  @spec create_for_issue(String.t(), Path.t()) :: {:ok, workspace()} | {:error, term()}
  def create_for_issue(identifier, root) do
    key = workspace_key(identifier)

    with {:ok, path} <- path_for_issue(identifier, root) do
      created_now = not File.dir?(path)
      :ok = File.mkdir_p(path)
      {:ok, %{path: path, workspace_key: key, created_now: created_now}}
    end
  end

  defp inside_root?(workspace_path, root_path) do
    workspace_path != root_path and String.starts_with?(workspace_path <> "/", root_path <> "/")
  end
end
