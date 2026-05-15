# Symphony Phoenix Phase 8 Design

## Goal

Add dynamic `WORKFLOW.md` reload support.

## Scope

- Orchestrator reconfiguration API for updated settings and prompt templates.
- Reconfiguration applies poll interval, concurrency, state lists, hooks, workspace root, Codex
  settings, and prompt template for future runs.
- Workflow watcher process that polls file mtime, reloads changed workflow files, validates dispatch
  config, and applies last-known-good settings.
- Invalid reloads do not crash the service and are visible through watcher snapshot state.

## Out of Scope

- Native filesystem event backends; polling mtime is sufficient for this phase.
- Restarting in-flight Codex sessions after config changes.
- HTTP endpoint for watcher state.

## Testing

Tests use temporary `WORKFLOW.md` files, memory tracker config, and an isolated orchestrator.
