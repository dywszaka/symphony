defmodule Symphony.Workspace do
  @moduledoc """
  Creates isolated per-issue workspaces.
  """

  alias Symphony.Workspace.Hooks

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
    create_for_issue(identifier, root, %{})
  end

  @spec create_for_issue(String.t(), Path.t(), map()) :: {:ok, workspace()} | {:error, term()}
  def create_for_issue(identifier, root, hooks) when is_map(hooks) do
    key = workspace_key(identifier)

    with {:ok, path} <- path_for_issue(identifier, root) do
      created_now = not File.dir?(path)
      :ok = File.mkdir_p(path)
      workspace = %{path: path, workspace_key: key, created_now: created_now}

      if created_now do
        case Hooks.run(:after_create, Map.get(hooks, :after_create), path, hook_timeout(hooks)) do
          :ok ->
            {:ok, workspace}

          {:error, reason} ->
            File.rm_rf(path)
            {:error, reason}
        end
      else
        {:ok, workspace}
      end
    end
  end

  @spec remove_for_issue(String.t(), Path.t(), map()) :: :ok | {:error, term()}
  def remove_for_issue(identifier, root, hooks \\ %{}) when is_map(hooks) do
    with {:ok, path} <- path_for_issue(identifier, root) do
      if File.dir?(path) do
        Hooks.run(:before_remove, Map.get(hooks, :before_remove), path, hook_timeout(hooks))
        File.rm_rf(path)
      end

      :ok
    end
  end

  defp inside_root?(workspace_path, root_path) do
    workspace_path != root_path and String.starts_with?(workspace_path <> "/", root_path <> "/")
  end

  defp hook_timeout(hooks), do: Map.get(hooks, :timeout_ms, 60_000)
end
