# AGENTS.md

This file is the concise navigation entry point for coding agents working on Symphony.

## Start Here

1. Read [`SPEC.md`](SPEC.md); it is the single source of truth for product behavior, architecture,
   runtime semantics, and configuration contracts.
2. Read [`phoenix/README.md`](phoenix/README.md) for the maintained implementation status,
   supported commands, tracker configuration, HTTP API, and Docker usage.
3. Read [`docs/tasktracker-dynamic-tools-spec.md`](docs/tasktracker-dynamic-tools-spec.md) before
   changing TaskTracker write tools or workpad/comment/state behavior.
4. Use [`elixir/`](elixir/) only as historical/reference material when porting intent or edge
   cases into `phoenix/`.

## Source-Of-Truth Locations

- Product and architecture contract: [`SPEC.md`](SPEC.md)
- Maintained implementation guide: [`phoenix/README.md`](phoenix/README.md)
- Phoenix source: [`phoenix/lib/symphony/`](phoenix/lib/symphony/)
- Phoenix web-only source: [`phoenix/lib/symphony_web/`](phoenix/lib/symphony_web/)
- Phoenix tests: [`phoenix/test/`](phoenix/test/)
- TaskTracker dynamic tool contract:
  [`docs/tasktracker-dynamic-tools-spec.md`](docs/tasktracker-dynamic-tools-spec.md)
- Phoenix phase design records: [`docs/superpowers/specs/`](docs/superpowers/specs/)
- Phoenix phase execution plans: [`docs/superpowers/plans/`](docs/superpowers/plans/)
- Docker TaskTracker launcher: [`run-phoenix-tasktracker-docker.sh`](run-phoenix-tasktracker-docker.sh)

## Working Rules

- Future development must target [`phoenix/`](phoenix/).
- Do not add new production behavior to [`elixir/`](elixir/) unless the user explicitly requests it.
- When `SPEC.md` and code disagree, treat `SPEC.md` as authoritative unless the task is to revise
  the spec.
- Keep core runtime logic under `phoenix/lib/symphony/`; keep Phoenix/web-only surfaces under
  `phoenix/lib/symphony_web/`.
- Tracker-generic contracts belong under `phoenix/lib/symphony/tracker/`; tracker-specific code
  belongs under `phoenix/lib/symphony/linear/` or `phoenix/lib/symphony/tasktracker/`.
- Keep workspace safety strict: agent working directories must remain under the configured
  `workspace.root`.
- Preserve user changes already present in the worktree. Do not revert unrelated changes without
  explicit approval.

## Development Workflow

- Make the smallest coherent Phoenix change set that satisfies the spec-backed behavior.
- For TaskTracker writes, align implementation and tests with
  [`docs/tasktracker-dynamic-tools-spec.md`](docs/tasktracker-dynamic-tools-spec.md).
- If behavior or configuration changes, update [`phoenix/README.md`](phoenix/README.md) or the
  relevant workflow/example in the same change.
- After code changes are implemented and tests or verification pass, create a self-contained git
  commit for that change set before reporting completion or moving on.
- Treat current `.github/workflows/` jobs as legacy Elixir-oriented CI evidence; they are not the
  Phoenix acceptance gate.

## Commands

From [`phoenix/`](phoenix/):

- Install dependencies: `mix deps.get`
- Format: `mix format`
- Format check: `mix format --check-formatted`
- Compile: `mix compile`
- Test: `mix test`
- Run service: `mix run --no-halt`

Docker fallback from the repository root:

```bash
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$PWD/.docker_mix":/tmp/.mix \
  -v "$PWD":/app \
  -w /app/phoenix \
  elixir:1.19.5-otp-28-alpine \
  sh -lc "mix deps.get >/dev/null && mix format --check-formatted && mix test"
```

TaskTracker Docker launcher:

```bash
TASKTRACKER_TOKEN=... TASKTRACKER_PROJECT_KEY=... ./run-phoenix-tasktracker-docker.sh
```

## Testing And Acceptance

- Run focused tests for touched modules while iterating.
- Before handoff, run `mix format --check-formatted` and `mix test` from `phoenix/`, or the Docker
  fallback above when local Elixir/Mix is unavailable.
- Add focused tests for new runtime, tracker, runner, dynamic-tool, workspace, or web behavior.
- Do not update snapshots, fixtures, or docs to hide behavior changes; make the intended behavior
  explicit in the relevant spec or README.

## Custom Capabilities

- `run-phoenix-tasktracker-docker.sh` generates a TaskTracker workflow file under
  `.symphony-tasktracker-runtime/` and starts the Phoenix service in Docker.
- `scripts/tasktracker_multi_agent_demo.py` is local demo automation; do not treat it as product
  runtime code without checking the current task.
- Root planning files [`task_plan.md`](task_plan.md), [`progress.md`](progress.md), and
  [`findings.md`](findings.md) may contain active local execution notes, but durable behavior belongs
  in `SPEC.md`, `phoenix/README.md`, or `docs/`.

## Existing Research And Design Material

- Phase design docs in [`docs/superpowers/specs/`](docs/superpowers/specs/) capture historical
  Phoenix architecture decisions.
- Phase plans in [`docs/superpowers/plans/`](docs/superpowers/plans/) capture prior implementation
  sequencing and acceptance notes.
- [`elixir/AGENTS.md`](elixir/AGENTS.md) and [`elixir/README.md`](elixir/README.md) describe the
  historical implementation; use them for reference only.
