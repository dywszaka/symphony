# Symphony Phoenix Implementation Plan

Goal: Build a new Symphony implementation from `SPEC.md` using Elixir/OTP + Phoenix in a new directory, keeping the existing `elixir/` implementation only as a behavioral reference.

## Constraints

- New implementation must live outside `elixir/`.
- Existing `elixir/` code may inform behavior but must not be copied wholesale.
- `SPEC.md` is the source of truth. Ambiguous spec areas require discussion before implementation.
- Work proceeds in phases. Each phase must be implemented, tested, committed to git, and reported for user confirmation before the next phase starts.
- Use TDD for behavior changes: write failing tests, verify failure, implement, verify passing.

## Phases

| Phase | Status | Scope | Exit Criteria |
| --- | --- | --- | --- |
| 0. Design and scaffold plan | complete | Confirm architecture, directory name, and Phase 1 scope | Design document committed and approved by user |
| 1. Core OTP MVP | complete | New Mix/Phoenix project, workflow loader, typed config, memory tracker, workspace basics, orchestrator skeleton, health/state API | Tests pass, app boots locally, git commit created |
| 2. Scheduling semantics | complete | Poll loop, candidate sorting, claim/running/retry state, active/terminal reconciliation, backoff | Focused orchestration tests pass, git commit created |
| 3. Linear integration | complete | Linear GraphQL tracker adapter, pagination, normalization, error mapping | Adapter unit tests pass with mocked HTTP, git commit created |
| 4. Codex agent runner | pending | Prompt rendering, Codex app-server subprocess client, turn lifecycle, runtime events | Protocol/client tests pass using fake app-server, git commit created |
| 5. Workspace hooks and safety | pending | Path invariants, hook execution/timeout/failure semantics, terminal cleanup | Workspace tests pass, git commit created |
| 6. Observability dashboard | pending | Structured state snapshot, Phoenix JSON API, optional LiveView dashboard, token/rate-limit accounting | API/UI tests pass, git commit created |
| 7. End-to-end validation | pending | Memory tracker E2E, optional Linear/Codex live test harness, docs | Full local quality gate passes, git commit created |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| `elixir`, `mix`, and `mise` missing on PATH | Phase 1 preflight | Started Docker Desktop and verified `elixir:1.19.5-otp-28-alpine`; Phase 1 commands run through Docker. |
| Docker named volume for `/tmp/.mix` was root-owned | Phase 1 test command | Use a worktree-local `.docker_mix/` bind mount owned by the host user and ignored by git. |
