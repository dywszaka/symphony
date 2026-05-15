# Symphony Phoenix Phase 7 Design

## Goal

Add startup terminal workspace cleanup and deterministic local end-to-end coverage.

## Scope

- Orchestrator startup cleanup for issues currently in terminal states.
- Cleanup uses `tracker.fetch_issues_by_states(settings.tracker.terminal_states)`.
- Cleanup removes matching workspaces using issue identifiers and `before_remove` hook semantics.
- Cleanup failures are non-fatal to orchestrator startup.
- Local E2E test that exercises memory tracker dispatch, fake Codex updates, snapshot state, and
  normal continuation retry.

## Out of Scope

- Live Linear/Codex smoke tests.
- Dynamic `WORKFLOW.md` reload.
- LiveView dashboard.

## Testing

All tests use in-memory/fake tracker and fake runner modules. No network or live Codex calls occur.
