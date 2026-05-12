defmodule Symphony.Workflow.LoaderTest do
  use ExUnit.Case, async: true

  alias Symphony.Workflow.Loader

  test "loads prompt-only workflow files" do
    path = temp_workflow!("Prompt only\n")

    assert {:ok, %{config: %{}, prompt_template: "Prompt only"}} = Loader.load(path)
  end

  test "loads YAML front matter and trims prompt body" do
    path =
      temp_workflow!("""
      ---
      tracker:
        kind: memory
      polling:
        interval_ms: 1000
      ---

      Work on {{ issue.identifier }}.
      """)

    assert {:ok, workflow} = Loader.load(path)

    assert workflow.config == %{
             "tracker" => %{"kind" => "memory"},
             "polling" => %{"interval_ms" => 1000}
           }

    assert workflow.prompt_template == "Work on {{ issue.identifier }}."
  end

  test "returns missing_workflow_file when file cannot be read" do
    path = Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}.md")

    assert {:error, {:missing_workflow_file, ^path, :enoent}} = Loader.load(path)
  end

  test "rejects non-map front matter" do
    path =
      temp_workflow!("""
      ---
      - not-a-map
      ---
      Body
      """)

    assert {:error, :workflow_front_matter_not_a_map} = Loader.load(path)
  end

  defp temp_workflow!(content) do
    dir =
      Path.join(System.tmp_dir!(), "symphony-loader-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "WORKFLOW.md")
    File.write!(path, content)
    path
  end
end
