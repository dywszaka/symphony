defmodule Symphony.Codex.AppServerTest do
  use ExUnit.Case, async: true

  alias Symphony.Codex.AppServer
  alias Symphony.Tracker.Issue

  @issue %Issue{id: "issue-1", identifier: "MT-1", title: "Runner", state: "Todo"}

  test "starts a thread and completed turn through line-delimited JSON-RPC" do
    workspace = tmp_dir("workspace")
    log_path = Path.join(workspace, "fake.log")
    script_path = write_fake_server!(workspace, "happy_path.exs", happy_path_server())

    settings = settings("FAKE_LOG=#{shell_escape(log_path)} elixir #{shell_escape(script_path)}")
    parent = self()

    assert {:ok, session} = AppServer.start_session(workspace, settings)

    assert {:ok, result} =
             AppServer.run_turn(session, "Do the work", @issue,
               on_message: fn message -> send(parent, {:codex_message, message}) end
             )

    AppServer.stop_session(session)

    assert result.thread_id == "thread-1"
    assert result.turn_id == "turn-1"

    client_messages = read_client_messages(log_path)
    assert Enum.at(client_messages, 0)["method"] == "initialize"
    assert Enum.at(client_messages, 1)["method"] == "thread/start"
    assert get_in(Enum.at(client_messages, 1), ["params", "cwd"]) == workspace
    assert get_in(Enum.at(client_messages, 1), ["params", "approvalPolicy"]) == "never"
    assert Enum.at(client_messages, 2)["method"] == "turn/start"
    assert get_in(Enum.at(client_messages, 2), ["params", "threadId"]) == "thread-1"

    assert get_in(Enum.at(client_messages, 2), ["params", "input"]) == [
             %{"type" => "text", "text" => "Do the work"}
           ]

    assert get_in(Enum.at(client_messages, 2), ["params", "sandboxPolicy"]) == %{
             "type" => "readOnly"
           }

    assert Enum.at(client_messages, 3)["result"] == %{"decision" => "acceptForSession"}
    assert Enum.at(client_messages, 4)["result"]["success"] == false

    assert_received {:codex_message, %{event: :thread_token_usage_updated}}
    assert_received {:codex_message, %{event: :turn_completed}}
  end

  test "fails user-input requests instead of stalling" do
    workspace = tmp_dir("workspace-input")
    script_path = write_fake_server!(workspace, "input_required.exs", input_required_server())
    settings = settings("elixir #{shell_escape(script_path)}")

    assert {:ok, session} = AppServer.start_session(workspace, settings)

    assert {:error, {:turn_input_required, %{"reason" => "need human"}}} =
             AppServer.run_turn(session, "Do the work", @issue)

    AppServer.stop_session(session)
  end

  test "maps startup read timeout" do
    workspace = tmp_dir("workspace-timeout")
    script_path = write_fake_server!(workspace, "silent.exs", "Process.sleep(:infinity)\n")
    settings = settings("elixir #{shell_escape(script_path)}", read_timeout_ms: 50)

    assert {:error, :codex_read_timeout} = AppServer.start_session(workspace, settings)
  end

  test "maps turn stream timeout" do
    workspace = tmp_dir("workspace-turn-timeout")
    script_path = write_fake_server!(workspace, "turn_timeout.exs", turn_timeout_server())
    settings = settings("elixir #{shell_escape(script_path)}", turn_timeout_ms: 50)

    assert {:ok, session} = AppServer.start_session(workspace, settings)
    assert {:error, :codex_turn_timeout} = AppServer.run_turn(session, "Do the work", @issue)
    AppServer.stop_session(session)
  end

  defp settings(command, overrides \\ []) do
    %{
      codex: %{
        command: command,
        approval_policy: Keyword.get(overrides, :approval_policy, "never"),
        thread_sandbox: Keyword.get(overrides, :thread_sandbox),
        turn_sandbox_policy:
          Keyword.get(overrides, :turn_sandbox_policy, %{"type" => "readOnly"}),
        read_timeout_ms: Keyword.get(overrides, :read_timeout_ms, 500),
        turn_timeout_ms: Keyword.get(overrides, :turn_timeout_ms, 1_000)
      }
    }
  end

  defp happy_path_server do
    """
    log = System.fetch_env!("FAKE_LOG")
    read = fn -> IO.read(:line) |> String.trim_trailing() end
    append = fn line -> File.write!(log, line <> "\\n", [:append]) end

    append.(read.())
    IO.puts(~s({"id":1,"result":{"codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"linux","userAgent":"fake"}}))

    append.(read.())
    IO.puts(~s({"id":2,"result":{"thread":{"id":"thread-1"},"cwd":"#{File.cwd!()}","model":"gpt-test","modelProvider":"openai","approvalPolicy":"never","approvalsReviewer":"user","sandbox":{"type":"readOnly"}}}))

    append.(read.())
    IO.puts(~s({"id":3,"result":{"turn":{"id":"turn-1"}}}))
    IO.puts(~s({"id":"approval-1","method":"item/commandExecution/requestApproval","params":{"command":"mix test"}}))
    append.(read.())
    IO.puts(~s({"id":"tool-1","method":"item/tool/call","params":{"name":"unknown_tool","arguments":{}}}))
    append.(read.())
    IO.puts(~s({"method":"thread/tokenUsage/updated","params":{"threadId":"thread-1","turnId":"turn-1","tokenUsage":{"last":{"inputTokens":1,"cachedInputTokens":0,"outputTokens":2,"reasoningOutputTokens":0,"totalTokens":3},"total":{"inputTokens":1,"cachedInputTokens":0,"outputTokens":2,"reasoningOutputTokens":0,"totalTokens":3}}}}))
    IO.puts(~s({"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}))
    Process.sleep(:infinity)
    """
  end

  defp input_required_server do
    """
    read = fn -> IO.read(:line) end
    read.()
    IO.puts(~s({"id":1,"result":{"codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"linux","userAgent":"fake"}}))
    read.()
    IO.puts(~s({"id":2,"result":{"thread":{"id":"thread-1"},"cwd":"#{File.cwd!()}","model":"gpt-test","modelProvider":"openai","approvalPolicy":"never","approvalsReviewer":"user","sandbox":{"type":"readOnly"}}}))
    read.()
    IO.puts(~s({"id":3,"result":{"turn":{"id":"turn-1"}}}))
    IO.puts(~s({"id":"input-1","method":"item/tool/requestUserInput","params":{"reason":"need human"}}))
    Process.sleep(:infinity)
    """
  end

  defp turn_timeout_server do
    """
    read = fn -> IO.read(:line) end
    read.()
    IO.puts(~s({"id":1,"result":{"codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"linux","userAgent":"fake"}}))
    read.()
    IO.puts(~s({"id":2,"result":{"thread":{"id":"thread-1"},"cwd":"#{File.cwd!()}","model":"gpt-test","modelProvider":"openai","approvalPolicy":"never","approvalsReviewer":"user","sandbox":{"type":"readOnly"}}}))
    read.()
    IO.puts(~s({"id":3,"result":{"turn":{"id":"turn-1"}}}))
    Process.sleep(:infinity)
    """
  end

  defp write_fake_server!(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp read_client_messages(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp tmp_dir(name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "symphony-app-server-#{name}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp shell_escape(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end
