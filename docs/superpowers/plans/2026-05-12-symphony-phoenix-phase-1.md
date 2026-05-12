# Symphony Phoenix Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase 1 Core OTP MVP for a new Elixir/OTP + Phoenix Symphony implementation in `phoenix/`.

**Architecture:** The core runtime lives under `phoenix/lib/symphony/` and has no dependency on Phoenix web modules. Phoenix modules under `phoenix/lib/symphony_web/` expose minimal health and state endpoints by calling public core APIs. Phase 1 uses a memory tracker and does not integrate Linear or Codex.

**Tech Stack:** Elixir 1.19 / OTP 28, Mix, Phoenix, Bandit, Jason, YAML parser, ExUnit.

---

## File Structure

- Create `phoenix/mix.exs`: Mix project with app name `:symphony`, Phoenix/Bandit/Jason/YAML deps, ExUnit config.
- Create `phoenix/config/config.exs`: endpoint and JSON library config.
- Create `phoenix/config/test.exs`: test endpoint config.
- Create `phoenix/lib/symphony/application.ex`: OTP supervision tree.
- Create `phoenix/lib/symphony/workflow/loader.ex`: `WORKFLOW.md` loader and parser.
- Create `phoenix/lib/symphony/config/settings.ex`: typed settings parser and preflight validation.
- Create `phoenix/lib/symphony/tracker/issue.ex`: normalized issue struct.
- Create `phoenix/lib/symphony/tracker/behaviour.ex`: tracker read contract.
- Create `phoenix/lib/symphony/tracker/memory.ex`: deterministic in-memory tracker.
- Create `phoenix/lib/symphony/workspace.ex`: workspace key/path/create logic.
- Create `phoenix/lib/symphony/orchestrator/state.ex`: runtime state struct and JSON-safe snapshot conversion.
- Create `phoenix/lib/symphony/orchestrator.ex`: GenServer owner of runtime state.
- Create `phoenix/lib/symphony_web/endpoint.ex`: Phoenix endpoint.
- Create `phoenix/lib/symphony_web/router.ex`: routes for `/health` and `/api/v1/state`.
- Create `phoenix/lib/symphony_web/controllers/health_controller.ex`: health JSON controller.
- Create `phoenix/lib/symphony_web/controllers/state_controller.ex`: state JSON controller.
- Create `phoenix/test/test_helper.exs`: ExUnit startup.
- Create `phoenix/test/support/conn_case.ex`: Phoenix connection test case.
- Create tests under `phoenix/test/symphony/` and `phoenix/test/symphony_web/`.
- Modify `task_plan.md`: mark Phase 0 complete and Phase 1 in progress/complete as appropriate.
- Modify `progress.md`: record implementation milestones, test results, and final commit.

## Preflight

- [ ] **Step 1: Verify Elixir toolchain**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony
elixir --version
mix --version
```

Expected: both commands print versions. If either command is missing, stop implementation and install/configure Elixir 1.19 with OTP 28 before continuing. Do not scaffold code until `mix` is available.

### Task 1: Scaffold Minimal Phoenix Project

**Files:**
- Create: `phoenix/mix.exs`
- Create: `phoenix/config/config.exs`
- Create: `phoenix/config/test.exs`
- Create: `phoenix/lib/symphony/application.ex`
- Create: `phoenix/lib/symphony_web/endpoint.ex`
- Create: `phoenix/lib/symphony_web/router.ex`
- Create: `phoenix/test/test_helper.exs`
- Create: `phoenix/test/support/conn_case.ex`

- [ ] **Step 1: Create minimal project files**

Create `phoenix/mix.exs`:

```elixir
defmodule Symphony.MixProject do
  use Mix.Project

  def project do
    [
      app: :symphony,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Symphony.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:phoenix, "~> 1.8.0"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
```

Create `phoenix/config/config.exs`:

```elixir
import Config

config :symphony, SymphonyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SymphonyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: nil,
  live_view: [signing_salt: "phase1-symphony"]

config :phoenix, :json_library, Jason
```

Create `phoenix/config/test.exs`:

```elixir
import Config

config :symphony, SymphonyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64)
```

Create `phoenix/lib/symphony/application.ex`:

```elixir
defmodule Symphony.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Symphony.Orchestrator,
      SymphonyWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Symphony.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SymphonyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

Create `phoenix/lib/symphony_web/endpoint.ex`:

```elixir
defmodule SymphonyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :symphony

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:json], pass: ["*/*"], json_decoder: Phoenix.json_library()
  plug SymphonyWeb.Router
end
```

Create `phoenix/lib/symphony_web/router.ex`:

```elixir
defmodule SymphonyWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SymphonyWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/api/v1/state", StateController, :show
  end
end
```

Create `phoenix/test/test_helper.exs`:

```elixir
ExUnit.start()
```

Create `phoenix/test/support/conn_case.ex`:

```elixir
defmodule SymphonyWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint SymphonyWeb.Endpoint
      use Phoenix.ConnTest
    end
  end
end
```

- [ ] **Step 2: Fetch dependencies**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix deps.get
```

Expected: dependencies resolve successfully.

- [ ] **Step 3: Run baseline compile**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix compile
```

Expected: compile fails because referenced modules such as `Symphony.Orchestrator`, `SymphonyWeb.HealthController`, `SymphonyWeb.StateController`, and `SymphonyWeb.ErrorJSON` do not exist yet. This is acceptable before Task 6 and Task 7. Do not commit yet.

### Task 2: Workflow Loader

**Files:**
- Create: `phoenix/test/symphony/workflow/loader_test.exs`
- Create: `phoenix/lib/symphony/workflow/loader.ex`

- [ ] **Step 1: Write failing loader tests**

Create `phoenix/test/symphony/workflow/loader_test.exs`:

```elixir
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
    assert workflow.config == %{"tracker" => %{"kind" => "memory"}, "polling" => %{"interval_ms" => 1000}}
    assert workflow.prompt_template == "Work on {{ issue.identifier }}."
  end

  test "returns missing_workflow_file when file cannot be read" do
    path = Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}.md")

    assert {:error, {:missing_workflow_file, ^path, :enoent}} = Loader.load(path)
  end

  test "rejects non-map front matter" do
    path = temp_workflow!("""
    ---
    - not-a-map
    ---
    Body
    """)

    assert {:error, :workflow_front_matter_not_a_map} = Loader.load(path)
  end

  defp temp_workflow!(content) do
    dir = Path.join(System.tmp_dir!(), "symphony-loader-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "WORKFLOW.md")
    File.write!(path, content)
    path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/workflow/loader_test.exs
```

Expected: FAIL with `module Symphony.Workflow.Loader is not loaded`.

- [ ] **Step 3: Implement loader**

Create `phoenix/lib/symphony/workflow/loader.ex`:

```elixir
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
```

- [ ] **Step 4: Run loader tests to verify they pass**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/workflow/loader_test.exs
```

Expected: PASS.

### Task 3: Config Settings

**Files:**
- Create: `phoenix/test/symphony/config/settings_test.exs`
- Create: `phoenix/lib/symphony/config/settings.ex`

- [ ] **Step 1: Write failing config tests**

Create `phoenix/test/symphony/config/settings_test.exs`:

```elixir
defmodule Symphony.Config.SettingsTest do
  use ExUnit.Case, async: true

  alias Symphony.Config.Settings

  test "applies spec defaults" do
    workflow_path = temp_workflow_path!()

    assert {:ok, settings} = Settings.from_workflow(%{config: %{}, prompt_template: ""}, workflow_path)
    assert settings.tracker.endpoint == "https://api.linear.app/graphql"
    assert settings.tracker.active_states == ["Todo", "In Progress"]
    assert settings.tracker.terminal_states == ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    assert settings.polling.interval_ms == 30_000
    assert settings.workspace.root == Path.join(System.tmp_dir!(), "symphony_workspaces")
    assert settings.hooks.timeout_ms == 60_000
    assert settings.agent.max_concurrent_agents == 10
    assert settings.agent.max_turns == 20
    assert settings.agent.max_retry_backoff_ms == 300_000
    assert settings.agent.max_concurrent_agents_by_state == %{}
    assert settings.codex.command == "codex app-server"
    assert settings.codex.turn_timeout_ms == 3_600_000
    assert settings.codex.read_timeout_ms == 5_000
    assert settings.codex.stall_timeout_ms == 300_000
  end

  test "resolves env-backed secrets and paths" do
    env_name = "SYMPHONY_PHASE1_ROOT_#{System.unique_integer([:positive])}"
    token_name = "SYMPHONY_PHASE1_TOKEN_#{System.unique_integer([:positive])}"
    root = Path.join(System.tmp_dir!(), "phase1-root")
    System.put_env(env_name, root)
    System.put_env(token_name, "secret")

    on_exit(fn ->
      System.delete_env(env_name)
      System.delete_env(token_name)
    end)

    workflow = %{
      config: %{
        "tracker" => %{"kind" => "linear", "api_key" => "$#{token_name}", "project_slug" => "proj"},
        "workspace" => %{"root" => "$#{env_name}"}
      },
      prompt_template: ""
    }

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert settings.tracker.api_key == "secret"
    assert settings.workspace.root == Path.expand(root)
  end

  test "resolves relative workspace root from workflow directory" do
    workflow_path = temp_workflow_path!()

    workflow = %{
      config: %{"workspace" => %{"root" => "tmp/workspaces"}},
      prompt_template: ""
    }

    assert {:ok, settings} = Settings.from_workflow(workflow, workflow_path)
    assert settings.workspace.root == Path.expand("tmp/workspaces", Path.dirname(workflow_path))
  end

  test "validates memory tracker without Linear credentials" do
    workflow = %{config: %{"tracker" => %{"kind" => "memory"}}, prompt_template: ""}

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert :ok = Settings.validate_dispatch(settings)
  end

  test "validates Linear dispatch requirements" do
    workflow = %{config: %{"tracker" => %{"kind" => "linear"}}, prompt_template: ""}

    assert {:ok, settings} = Settings.from_workflow(workflow, temp_workflow_path!())
    assert {:error, :missing_linear_api_token} = Settings.validate_dispatch(settings)
  end

  defp temp_workflow_path! do
    dir = Path.join(System.tmp_dir!(), "symphony-settings-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Path.join(dir, "WORKFLOW.md")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/config/settings_test.exs
```

Expected: FAIL with `module Symphony.Config.Settings is not loaded`.

- [ ] **Step 3: Implement settings**

Create `phoenix/lib/symphony/config/settings.ex`:

```elixir
defmodule Symphony.Config.Settings do
  @moduledoc """
  Typed runtime settings derived from workflow front matter.
  """

  defstruct tracker: %{},
            polling: %{},
            workspace: %{},
            hooks: %{},
            agent: %{},
            codex: %{}

  @type t :: %__MODULE__{}

  @spec from_workflow(%{config: map()}, Path.t()) :: {:ok, t()} | {:error, term()}
  def from_workflow(%{config: config}, workflow_path) when is_map(config) and is_binary(workflow_path) do
    normalized = normalize_keys(config)

    settings = %__MODULE__{
      tracker: tracker_settings(Map.get(normalized, "tracker", %{})),
      polling: polling_settings(Map.get(normalized, "polling", %{})),
      workspace: workspace_settings(Map.get(normalized, "workspace", %{}), workflow_path),
      hooks: hooks_settings(Map.get(normalized, "hooks", %{})),
      agent: agent_settings(Map.get(normalized, "agent", %{})),
      codex: codex_settings(Map.get(normalized, "codex", %{}))
    }

    {:ok, settings}
  rescue
    error in ArgumentError -> {:error, {:invalid_workflow_config, Exception.message(error)}}
  end

  @spec validate_dispatch(t()) :: :ok | {:error, term()}
  def validate_dispatch(%__MODULE__{} = settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      settings.tracker.kind not in ["linear", "memory"] ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      settings.tracker.kind == "linear" and blank?(settings.tracker.api_key) ->
        {:error, :missing_linear_api_token}

      settings.tracker.kind == "linear" and blank?(settings.tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      blank?(settings.codex.command) ->
        {:error, {:invalid_workflow_config, "codex.command can't be blank"}}

      true ->
        :ok
    end
  end

  defp tracker_settings(raw) do
    %{
      kind: string_or_nil(raw["kind"]),
      endpoint: string_or_nil(raw["endpoint"]) || "https://api.linear.app/graphql",
      api_key: resolve_secret(raw["api_key"], System.get_env("LINEAR_API_KEY")),
      project_slug: string_or_nil(raw["project_slug"]),
      active_states: string_list(raw["active_states"], ["Todo", "In Progress"]),
      terminal_states: string_list(raw["terminal_states"], ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"])
    }
  end

  defp polling_settings(raw), do: %{interval_ms: positive_integer(raw["interval_ms"], 30_000, "polling.interval_ms")}

  defp workspace_settings(raw, workflow_path) do
    root =
      raw
      |> Map.get("root", Path.join(System.tmp_dir!(), "symphony_workspaces"))
      |> resolve_path(Path.dirname(workflow_path))

    %{root: root}
  end

  defp hooks_settings(raw), do: %{timeout_ms: positive_integer(raw["timeout_ms"], 60_000, "hooks.timeout_ms")}

  defp agent_settings(raw) do
    %{
      max_concurrent_agents: positive_integer(raw["max_concurrent_agents"], 10, "agent.max_concurrent_agents"),
      max_turns: positive_integer(raw["max_turns"], 20, "agent.max_turns"),
      max_retry_backoff_ms: positive_integer(raw["max_retry_backoff_ms"], 300_000, "agent.max_retry_backoff_ms"),
      max_concurrent_agents_by_state: normalize_state_limits(raw["max_concurrent_agents_by_state"])
    }
  end

  defp codex_settings(raw) do
    %{
      command: string_or_nil(raw["command"]) || "codex app-server",
      approval_policy: raw["approval_policy"],
      thread_sandbox: raw["thread_sandbox"],
      turn_sandbox_policy: raw["turn_sandbox_policy"],
      turn_timeout_ms: positive_integer(raw["turn_timeout_ms"], 3_600_000, "codex.turn_timeout_ms"),
      read_timeout_ms: positive_integer(raw["read_timeout_ms"], 5_000, "codex.read_timeout_ms"),
      stall_timeout_ms: non_negative_integer(raw["stall_timeout_ms"], 300_000, "codex.stall_timeout_ms")
    }
  end

  defp normalize_keys(value) when is_map(value), do: Map.new(value, fn {key, val} -> {to_string(key), normalize_keys(val)} end)
  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp string_or_nil(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp string_or_nil(_value), do: nil

  defp string_list(nil, default), do: default
  defp string_list(values, _default) when is_list(values), do: Enum.map(values, &to_string/1)
  defp string_list(_values, _default), do: raise(ArgumentError, "state lists must be arrays")

  defp positive_integer(nil, default, _field), do: default
  defp positive_integer(value, _default, field) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, _default, field), do: raise(ArgumentError, "#{field} must be a positive integer")

  defp non_negative_integer(nil, default, _field), do: default
  defp non_negative_integer(value, _default, field) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, _default, field), do: raise(ArgumentError, "#{field} must be a non-negative integer")

  defp resolve_secret(nil, fallback), do: normalize_secret(fallback)
  defp resolve_secret(value, fallback) when is_binary(value), do: value |> resolve_env_reference(fallback) |> normalize_secret()
  defp resolve_secret(_value, _fallback), do: nil

  defp normalize_secret(value) when is_binary(value), do: if(value == "", do: nil, else: value)
  defp normalize_secret(_value), do: nil

  defp resolve_path(value, workflow_dir) when is_binary(value) do
    value
    |> resolve_env_reference(nil)
    |> case do
      nil -> Path.join(System.tmp_dir!(), "symphony_workspaces")
      "" -> Path.join(System.tmp_dir!(), "symphony_workspaces")
      "~" -> System.user_home!()
      "~/" <> rest -> Path.join(System.user_home!(), rest)
      path -> if Path.type(path) == :relative, do: Path.expand(path, workflow_dir), else: Path.expand(path)
    end
  end

  defp resolve_path(_value, _workflow_dir), do: Path.join(System.tmp_dir!(), "symphony_workspaces")

  defp resolve_env_reference("$" <> env_name, fallback) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, env_name) do
      case System.get_env(env_name) do
        nil -> fallback
        "" -> nil
        value -> value
      end
    else
      "$" <> env_name
    end
  end

  defp resolve_env_reference(value, _fallback), do: value

  defp normalize_state_limits(nil), do: %{}

  defp normalize_state_limits(limits) when is_map(limits) do
    Map.new(limits, fn {state, limit} ->
      unless is_integer(limit) and limit > 0, do: raise(ArgumentError, "agent.max_concurrent_agents_by_state values must be positive integers")
      {state |> to_string() |> String.downcase(), limit}
    end)
  end

  defp normalize_state_limits(_limits), do: raise(ArgumentError, "agent.max_concurrent_agents_by_state must be a map")

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
```

- [ ] **Step 4: Run config tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/config/settings_test.exs
```

Expected: PASS.

### Task 4: Memory Tracker

**Files:**
- Create: `phoenix/test/symphony/tracker/memory_test.exs`
- Create: `phoenix/lib/symphony/tracker/issue.ex`
- Create: `phoenix/lib/symphony/tracker/behaviour.ex`
- Create: `phoenix/lib/symphony/tracker/memory.ex`

- [ ] **Step 1: Write failing memory tracker tests**

Create `phoenix/test/symphony/tracker/memory_test.exs`:

```elixir
defmodule Symphony.Tracker.MemoryTest do
  use ExUnit.Case, async: false

  alias Symphony.Tracker.{Issue, Memory}

  setup do
    Memory.put_issues([])
    :ok
  end

  test "fetch_candidate_issues returns configured memory issues" do
    issue = %Issue{id: "1", identifier: "MT-1", title: "Build", state: "Todo", labels: ["Backend"]}
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/tracker/memory_test.exs
```

Expected: FAIL with missing tracker modules.

- [ ] **Step 3: Implement tracker modules**

Create `phoenix/lib/symphony/tracker/issue.ex`:

```elixir
defmodule Symphony.Tracker.Issue do
  @moduledoc """
  Normalized issue record used by orchestration.
  """

  defstruct id: nil,
            identifier: nil,
            title: nil,
            description: nil,
            priority: nil,
            state: nil,
            branch_name: nil,
            url: nil,
            labels: [],
            blocked_by: [],
            created_at: nil,
            updated_at: nil

  @type t :: %__MODULE__{}

  @spec normalize(t() | map()) :: t()
  def normalize(%__MODULE__{} = issue), do: %{issue | labels: normalize_labels(issue.labels)}

  def normalize(map) when is_map(map) do
    struct(__MODULE__, map)
    |> normalize()
  end

  defp normalize_labels(labels) when is_list(labels), do: Enum.map(labels, &(to_string(&1) |> String.downcase()))
  defp normalize_labels(_labels), do: []
end
```

Create `phoenix/lib/symphony/tracker/behaviour.ex`:

```elixir
defmodule Symphony.Tracker.Behaviour do
  @moduledoc """
  Tracker read contract required by the orchestrator.
  """

  alias Symphony.Tracker.Issue

  @callback fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
end
```

Create `phoenix/lib/symphony/tracker/memory.ex`:

```elixir
defmodule Symphony.Tracker.Memory do
  @moduledoc """
  In-memory tracker adapter for tests and local Phase 1 validation.
  """

  @behaviour Symphony.Tracker.Behaviour

  alias Symphony.Tracker.Issue

  @app :symphony
  @key :memory_tracker_issues

  @spec put_issues([Issue.t() | map()]) :: :ok
  def put_issues(issues) when is_list(issues) do
    Application.put_env(@app, @key, Enum.map(issues, &Issue.normalize/1))
    :ok
  end

  @impl true
  def fetch_candidate_issues, do: {:ok, issues()}

  @impl true
  def fetch_issues_by_states(states) when is_list(states) do
    wanted = MapSet.new(Enum.map(states, &normalize_state/1))
    {:ok, Enum.filter(issues(), &(normalize_state(&1.state) in wanted))}
  end

  @impl true
  def fetch_issue_states_by_ids(ids) when is_list(ids) do
    wanted = MapSet.new(ids)
    {:ok, Enum.filter(issues(), &(&1.id in wanted))}
  end

  defp issues, do: Application.get_env(@app, @key, [])
  defp normalize_state(state), do: state |> to_string() |> String.downcase()
end
```

- [ ] **Step 4: Run tracker tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/tracker/memory_test.exs
```

Expected: PASS.

### Task 5: Workspace Basics

**Files:**
- Create: `phoenix/test/symphony/workspace_test.exs`
- Create: `phoenix/lib/symphony/workspace.ex`

- [ ] **Step 1: Write failing workspace tests**

Create `phoenix/test/symphony/workspace_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/workspace_test.exs
```

Expected: FAIL with `module Symphony.Workspace is not loaded`.

- [ ] **Step 3: Implement workspace basics**

Create `phoenix/lib/symphony/workspace.ex`:

```elixir
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
```

- [ ] **Step 4: Run workspace tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/workspace_test.exs
```

Expected: PASS.

### Task 6: Orchestrator State and Snapshot

**Files:**
- Create: `phoenix/test/symphony/orchestrator_test.exs`
- Create: `phoenix/lib/symphony/orchestrator/state.ex`
- Create: `phoenix/lib/symphony/orchestrator.ex`

- [ ] **Step 1: Write failing orchestrator tests**

Create `phoenix/test/symphony/orchestrator_test.exs`:

```elixir
defmodule Symphony.OrchestratorTest do
  use ExUnit.Case, async: false

  alias Symphony.Orchestrator

  test "starts and exposes a spec-shaped snapshot" do
    start_supervised!({Orchestrator, name: :phase1_orchestrator_test})

    assert {:ok, snapshot} = Orchestrator.snapshot(:phase1_orchestrator_test)
    assert snapshot.poll_interval_ms == 30_000
    assert snapshot.max_concurrent_agents == 10
    assert snapshot.running == %{}
    assert snapshot.claimed == []
    assert snapshot.retry_attempts == %{}
    assert snapshot.completed == []
    assert snapshot.codex_totals == %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0}
    assert snapshot.codex_rate_limits == nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/orchestrator_test.exs
```

Expected: FAIL with missing orchestrator modules.

- [ ] **Step 3: Implement orchestrator state and GenServer**

Create `phoenix/lib/symphony/orchestrator/state.ex`:

```elixir
defmodule Symphony.Orchestrator.State do
  @moduledoc """
  Runtime state owned by the orchestrator.
  """

  defstruct poll_interval_ms: 30_000,
            max_concurrent_agents: 10,
            running: %{},
            claimed: MapSet.new(),
            retry_attempts: %{},
            completed: MapSet.new(),
            codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
            codex_rate_limits: nil

  @type t :: %__MODULE__{}

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = state) do
    %{
      poll_interval_ms: state.poll_interval_ms,
      max_concurrent_agents: state.max_concurrent_agents,
      running: state.running,
      claimed: MapSet.to_list(state.claimed),
      retry_attempts: state.retry_attempts,
      completed: MapSet.to_list(state.completed),
      codex_totals: state.codex_totals,
      codex_rate_limits: state.codex_rate_limits
    }
  end
end
```

Create `phoenix/lib/symphony/orchestrator.ex`:

```elixir
defmodule Symphony.Orchestrator do
  @moduledoc """
  Owns Symphony runtime scheduling state.
  """

  use GenServer

  alias Symphony.Orchestrator.State

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, :unavailable}
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call(:snapshot, _from, %State{} = state) do
    {:reply, {:ok, State.snapshot(state)}, state}
  end
end
```

- [ ] **Step 4: Run orchestrator tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony/orchestrator_test.exs
```

Expected: PASS.

### Task 7: Phoenix Health and State API

**Files:**
- Create: `phoenix/test/symphony_web/health_controller_test.exs`
- Create: `phoenix/test/symphony_web/state_controller_test.exs`
- Create: `phoenix/lib/symphony_web/controllers/health_controller.ex`
- Create: `phoenix/lib/symphony_web/controllers/state_controller.ex`
- Create: `phoenix/lib/symphony_web/controllers/error_json.ex`

- [ ] **Step 1: Write failing controller tests**

Create `phoenix/test/symphony_web/health_controller_test.exs`:

```elixir
defmodule SymphonyWeb.HealthControllerTest do
  use SymphonyWeb.ConnCase, async: true

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
```

Create `phoenix/test/symphony_web/state_controller_test.exs`:

```elixir
defmodule SymphonyWeb.StateControllerTest do
  use SymphonyWeb.ConnCase, async: false

  test "GET /api/v1/state returns orchestrator snapshot", %{conn: conn} do
    conn = get(conn, "/api/v1/state")
    body = json_response(conn, 200)

    assert body["poll_interval_ms"] == 30_000
    assert body["max_concurrent_agents"] == 10
    assert body["running"] == %{}
    assert body["claimed"] == []
    assert body["retry_attempts"] == %{}
    assert body["completed"] == []
    assert body["codex_totals"] == %{"input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0, "seconds_running" => 0}
  end
end
```

- [ ] **Step 2: Run controller tests to verify they fail**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony_web
```

Expected: FAIL with missing controller modules.

- [ ] **Step 3: Implement controllers**

Create `phoenix/lib/symphony_web/controllers/health_controller.ex`:

```elixir
defmodule SymphonyWeb.HealthController do
  use Phoenix.Controller, formats: [:json]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
```

Create `phoenix/lib/symphony_web/controllers/state_controller.ex`:

```elixir
defmodule SymphonyWeb.StateController do
  use Phoenix.Controller, formats: [:json]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    case Symphony.Orchestrator.snapshot() do
      {:ok, snapshot} ->
        json(conn, snapshot)

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: to_string(reason)})
    end
  end
end
```

Create `phoenix/lib/symphony_web/controllers/error_json.ex`:

```elixir
defmodule SymphonyWeb.ErrorJSON do
  @moduledoc false

  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
```

- [ ] **Step 4: Run controller tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test test/symphony_web
```

Expected: PASS.

### Task 8: Full Phase 1 Verification and Commit

**Files:**
- Modify: `task_plan.md`
- Modify: `progress.md`

- [ ] **Step 1: Run formatter**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix format
```

Expected: command exits successfully.

- [ ] **Step 2: Run full Phase 1 tests**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
mix test
```

Expected: PASS.

- [ ] **Step 3: Verify app boots enough for routes**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony/phoenix
MIX_ENV=test mix run --no-halt
```

Expected: the app starts without crashing. Stop it manually after startup is observed.

- [ ] **Step 4: Update tracking files**

Modify `task_plan.md` so Phase 0 is `complete` and Phase 1 is `complete` after tests pass. Modify `progress.md` with:

```markdown
- Completed Phase 1 Core OTP MVP in `phoenix/`.
- Verified with `mix format` and `mix test` from `phoenix/`.
- Created Phase 1 commit.
```

- [ ] **Step 5: Commit Phase 1**

Run:

```bash
cd /Users/zhaoanka/Develop/symphony
git status --short
git add phoenix task_plan.md progress.md docs/superpowers/plans/2026-05-12-symphony-phoenix-phase-1.md
git commit -m "feat: scaffold phoenix core mvp"
```

Expected: commit succeeds. Report the commit hash and pause for user confirmation before Phase 2.

## Self-Review

- Spec coverage for Phase 1:
  - Workflow loading and front matter parsing: Task 2.
  - Core config defaults, env indirection, relative workspace root, and dispatch preflight validation: Task 3.
  - Memory tracker for deterministic tests: Task 4.
  - Workspace key and directory creation basics: Task 5.
  - Orchestrator-owned runtime state and snapshot: Task 6.
  - Minimal Phoenix observability endpoints: Task 7.
- Deferred spec sections are intentionally outside Phase 1 and listed in the design document.
- Type names used across tasks are consistent: `Symphony.Workflow.Loader`, `Symphony.Config.Settings`, `Symphony.Tracker.Issue`, `Symphony.Tracker.Memory`, `Symphony.Workspace`, `Symphony.Orchestrator`, and `Symphony.Orchestrator.State`.

