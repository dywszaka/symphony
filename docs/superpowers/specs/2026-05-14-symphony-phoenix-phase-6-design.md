# Symphony Phoenix Phase 6 Design

## Goal

Add runtime observability and stall handling to the Phoenix implementation.

## Scope

- Route Codex app-server update messages from runner processes into the orchestrator.
- Track per-running-entry session/event metadata.
- Aggregate token totals from `thread/tokenUsage/updated` payloads using total token deltas.
- Store the latest account rate-limit payload.
- Include runtime/event/token fields in `/api/v1/state` snapshots.
- Detect stalled running entries during reconciliation and schedule retries.

## Out of Scope

- LiveView dashboard.
- Dynamic workflow reload.
- Startup terminal workspace cleanup.
- Parsing every historical Codex protocol token shape; Phase 6 covers the generated local schema's
  `thread/tokenUsage/updated` shape and keeps extraction helpers isolated for later expansion.

## Testing

Tests use the existing fake runner and send orchestrator update messages directly or through the
runner callback. No live Codex process is launched.
