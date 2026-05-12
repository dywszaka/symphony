# Symphony Phoenix

This directory contains the new Elixir/OTP + Phoenix implementation of Symphony.

Status: Phase 1 Core OTP MVP.

The implementation is intentionally separate from `../elixir/`. The existing Elixir implementation
can be used as behavioral reference, but this project is developed from `../SPEC.md` as the source
of truth.

## What Works Now

- Workflow loading from `WORKFLOW.md`-style files.
- Typed runtime settings with core defaults.
- In-memory tracker for deterministic local tests.
- Workspace key/path creation basics.
- OTP orchestrator process with a runtime snapshot.
- Phoenix JSON endpoints:
  - `GET /health`
  - `GET /api/v1/state`

Not implemented yet:

- Linear GraphQL adapter.
- Codex app-server runner.
- Polling/dispatch/retry/reconciliation semantics.
- Workspace hooks.
- LiveView dashboard.

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

## Development Notes

- Keep core runtime code under `lib/symphony/`.
- Keep Phoenix/web-only code under `lib/symphony_web/`.
- Do not add Linear or Codex behavior to Phase 1 modules unless the next phase explicitly calls for
  it.
- Run `mix format` and `mix test` before committing changes.
