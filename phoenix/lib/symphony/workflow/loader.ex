defmodule Symphony.Workflow.Loader do
  @moduledoc """
  Loads workflow configuration and prompt templates from WORKFLOW.md files.
  """

  @type loaded_workflow :: %{
          config: map(),
          prompt_template: String.t()
        }

  @spec default_path() :: Path.t()
  def default_path, do: Path.join(File.cwd!(), "WORKFLOW.md")

  @spec load(Path.t()) :: {:ok, loaded_workflow()} | {:error, term()}
  def load(path \\ default_path()) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, {:missing_workflow_file, path, reason}}
    end
  end

  @spec parse(String.t()) :: {:ok, loaded_workflow()} | {:error, term()}
  def parse(content) when is_binary(content) do
    {front_matter_lines, prompt_lines} = split_front_matter(content)

    with {:ok, config} <- parse_front_matter(front_matter_lines) do
      {:ok, %{config: config, prompt_template: prompt_lines |> Enum.join("\n") |> String.trim()}}
    end
  end

  defp split_front_matter(content) do
    lines = String.split(content, ~r/\R/, trim: false)

    case lines do
      ["---" | tail] ->
        {front, rest} = Enum.split_while(tail, &(&1 != "---"))

        case rest do
          ["---" | prompt] -> {front, prompt}
          _ -> {front, []}
        end

      _ ->
        {[], lines}
    end
  end

  defp parse_front_matter([]), do: {:ok, %{}}

  defp parse_front_matter(lines) do
    yaml = Enum.join(lines, "\n")

    if String.trim(yaml) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml) do
        {:ok, value} when is_map(value) -> {:ok, value}
        {:ok, _other} -> {:error, :workflow_front_matter_not_a_map}
        {:error, reason} -> {:error, {:workflow_parse_error, reason}}
      end
    end
  end
end
