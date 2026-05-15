# Symphony Phoenix

This directory contains the new Elixir/OTP + Phoenix implementation of Symphony.

Status: Phase 8 Dynamic Workflow Reload.

The implementation is intentionally separate from `../elixir/`. The existing Elixir implementation
can be used as behavioral reference, but this project is developed from `../SPEC.md` as the source
of truth.

## What Works Now

- Workflow loading from `WORKFLOW.md`-style files.
- Typed runtime settings with core defaults.
- In-memory tracker for deterministic local tests.
- Linear GraphQL tracker adapter with pagination, state refresh, blocker extraction, and
  deterministic mocked tests.
- Strict prompt rendering for issue fields and retry attempts.
- Codex app-server runner/client with deterministic fake-protocol tests.
- Workspace lifecycle hooks with timeout and failure semantics.
- Codex update routing, token/rate-limit aggregation, and stall detection.
- Startup cleanup removes stale workspaces for terminal tracker issues.
- Deterministic local E2E orchestration coverage.
- Dynamic workflow reload watcher with last-known-good behavior for invalid reloads.
- Workspace key/path creation basics.
- OTP orchestrator process with dispatch, claim, running, retry, reconciliation, and runtime
  snapshot support.
- Candidate sorting and eligibility rules from `../SPEC.md`.
- In-memory scheduling tests with a fake runner.
- Phoenix JSON endpoints:
  - `GET /health`
  - `GET /api/v1/state`

Not implemented yet:

- LiveView dashboard.
- Optional `linear_graphql` dynamic tool extension.

## Requirements

Recommended runtime:

- Elixir `1.19.x`
- Erlang/OTP `28`

`mix` is installed with Elixir. If `mix --version` is missing, install Elixir first.

If Elixir is not installed locally, use the Docker commands below. They use the official
`elixir:1.19.5-otp-28-alpine` image.

## Install Elixir and Mix

### macOS with Homebrew

```bash
brew install elixir
elixir --version
mix --version
```

Homebrew may install a newer Elixir/OTP version than the recommended one. That is usually fine for
local Phase 1 work, but use the Docker commands below when you need the exact `1.19.5-otp-28`
runtime.

### macOS/Linux with mise

Install `mise`, then create or use a tool config that pins Elixir and Erlang:

```bash
brew install mise
mise use -g erlang@28
mise use -g elixir@1.19.5-otp-28
mise exec -- elixir --version
mise exec -- mix --version
```

Run Mix commands through `mise exec`:

```bash
cd phoenix
mise exec -- mix deps.get
mise exec -- mix test
```

### macOS/Linux with asdf

```bash
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 28.0
asdf install elixir 1.19.5-otp-28
asdf local erlang 28.0
asdf local elixir 1.19.5-otp-28
elixir --version
mix --version
```

## Local Elixir Usage

From this directory:

```bash
cd phoenix
mix deps.get
mix test
```

Common Mix commands:

```bash
mix deps.get      # install project dependencies
mix compile       # compile the application
mix format        # format Elixir source files
mix test          # run the test suite
mix run --no-halt # start the OTP application without returning to the shell
```

Run the application with an HTTP listener:

```bash
cd phoenix
mix run --no-start -e 'config = Application.get_env(:symphony, SymphonyWeb.Endpoint, []); Application.put_env(:symphony, SymphonyWeb.Endpoint, Keyword.merge(config, http: [ip: {127, 0, 0, 1}, port: 4002], server: true, secret_key_base: String.duplicate("a", 64))); Application.ensure_all_started(:symphony); Process.sleep(:infinity)'
```

Then verify:

```bash
curl http://127.0.0.1:4002/health
curl http://127.0.0.1:4002/api/v1/state
```

## Docker Usage

From the repository root:

```bash
mkdir -p .docker_mix
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$PWD/.docker_mix":/tmp/.mix \
  -v "$PWD":/app \
  -w /app/phoenix \
  elixir:1.19.5-otp-28-alpine \
  sh -lc "mix local.hex --force && mix deps.get && mix test"
```

Run the HTTP API through Docker:

```bash
mkdir -p .docker_mix
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -p 4002:4002 \
  -v "$PWD/.docker_mix":/tmp/.mix \
  -v "$PWD":/app \
  -w /app/phoenix \
  elixir:1.19.5-otp-28-alpine \
  sh -lc 'mix deps.get && mix run --no-start -e '\''config = Application.get_env(:symphony, SymphonyWeb.Endpoint, []); Application.put_env(:symphony, SymphonyWeb.Endpoint, Keyword.merge(config, http: [ip: {0, 0, 0, 0}, port: 4002], server: true, secret_key_base: String.duplicate("a", 64))); Application.ensure_all_started(:symphony); Process.sleep(:infinity)'\'''
```

Then, in another terminal:

```bash
curl http://127.0.0.1:4002/health
curl http://127.0.0.1:4002/api/v1/state
```

## API Responses

`GET /health`

```json
{"status":"ok"}
```

`GET /api/v1/state`

```json
{
  "poll_interval_ms": 30000,
  "max_concurrent_agents": 10,
  "running": {},
  "claimed": [],
  "retry_attempts": {},
  "completed": [],
  "codex_totals": {
    "input_tokens": 0,
    "output_tokens": 0,
    "total_tokens": 0,
    "seconds_running": 0
  },
  "codex_rate_limits": null
}
```

## Linear Tracker Configuration

Linear settings are parsed from workflow front matter. The adapter uses `LINEAR_API_KEY` when
`tracker.api_key` is omitted.

```yaml
tracker:
  kind: linear
  endpoint: https://api.linear.app/graphql
  project_slug: my-project
  api_key: ${LINEAR_API_KEY}
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Canceled
```

## Codex Runner Policy

The Phase 4 runner starts `codex app-server` with `bash -lc <codex.command>` from the per-issue
workspace. It follows the current local app-server JSON-RPC protocol:

- `initialize`
- `thread/start`
- `turn/start`

Approval posture for this phase:

- Command execution approval requests are accepted for the session.
- File-change approval requests are accepted for the session.
- Unsupported dynamic tools return a structured tool failure.
- User-input requests fail the current turn so runs do not stall indefinitely.

## Workspace Hooks

Supported hook fields in workflow front matter:

```yaml
hooks:
  timeout_ms: 60000
  after_create: |
    echo "new workspace: $PWD"
  before_run: |
    echo "before Codex: $PWD"
  after_run: |
    echo "after Codex: $PWD"
  before_remove: |
    echo "removing workspace: $PWD"
```

`after_create` and `before_run` failures abort the current operation. `after_run` and
`before_remove` failures are logged and ignored.

## Runtime Observability

The JSON state API includes running-entry Codex metadata when available:

- `session_id`
- `last_codex_event`
- `last_codex_timestamp_ms`
- `codex_input_tokens`
- `codex_output_tokens`
- `codex_total_tokens`

Aggregate `codex_totals` are updated from total token-usage events, and `codex_rate_limits` stores
the latest rate-limit payload seen from Codex.

## Startup Cleanup

When the orchestrator starts with workspace settings, it queries terminal tracker states and removes
matching issue workspaces. Cleanup errors are treated as non-fatal startup warnings.

## Dynamic Workflow Reload

`Symphony.Workflow.Watcher` can watch a `WORKFLOW.md` path and apply valid changes to a running
orchestrator:

```elixir
{:ok, watcher} =
  Symphony.Workflow.Watcher.start_link(
    workflow_path: "/path/to/WORKFLOW.md",
    orchestrator: Symphony.Orchestrator
  )
```

Invalid reloads keep the last-known-good settings and prompt template. Inspect watcher state with
`Symphony.Workflow.Watcher.snapshot(watcher)`.

## Development Notes

- Keep core runtime code under `lib/symphony/`.
- Keep Phoenix/web-only code under `lib/symphony_web/`.
- Do not add dynamic Codex tool extensions until the relevant phase explicitly calls for them.
- Run `mix format` and `mix test` before committing changes.
