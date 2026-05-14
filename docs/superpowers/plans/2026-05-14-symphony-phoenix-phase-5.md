# Symphony Phoenix Phase 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement workspace hooks and safety checks from `SPEC.md`.

**Architecture:** Add a focused hook executor under `Symphony.Workspace.Hooks`, extend
`Symphony.Workspace` for hook-aware create/remove operations, and integrate `before_run`/`after_run`
in `Symphony.Runner.Codex`. Tests run shell snippets in temporary workspaces and fake the app-server
where runner behavior is under test.

**Tech Stack:** Elixir 1.19 / OTP 28, POSIX `sh`, ExUnit.

---

## Tasks

- [x] Add hook executor tests for success, non-zero exit, timeout, and cwd.
- [x] Implement `Symphony.Workspace.Hooks`.
- [x] Add workspace tests for `after_create` fatal behavior and `before_remove` best-effort cleanup.
- [x] Extend `Symphony.Workspace` with hook-aware create/remove helpers.
- [x] Add runner tests for `before_run` abort, `after_run` best-effort execution, and cwd safety.
- [x] Integrate hooks and workspace cwd validation into `Symphony.Runner.Codex`.
- [x] Update README, task plan, and progress notes.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 5.
