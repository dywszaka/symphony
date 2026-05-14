# Symphony Phoenix Phase 5 Design

## Goal

Implement workspace hooks and safety semantics from `SPEC.md` for the Phoenix implementation.

## Scope

- Hook executor for `after_create`, `before_run`, `after_run`, and `before_remove`.
- POSIX shell execution with `sh -lc <script>` in the workspace directory.
- Timeout enforcement using `hooks.timeout_ms`.
- Fatal failure semantics for `after_create` and `before_run`.
- Best-effort/log-and-ignore semantics for `after_run` and `before_remove`.
- Workspace removal helper that runs `before_remove` before deleting an existing workspace.
- Runner integration for `before_run`/`after_run`.
- Safety validation that the Codex app-server launch cwd equals the computed per-issue workspace.

## Out of Scope

- Dynamic workflow reload.
- Startup terminal workspace cleanup from live Linear state.
- Orchestrator-driven terminal cleanup of running entries.
- Cross-platform Windows shell behavior.

## Testing

Tests use local shell scripts and fake app-server modules. No live Codex or Linear calls occur.
