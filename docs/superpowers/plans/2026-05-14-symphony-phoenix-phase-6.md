# Symphony Phoenix Phase 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime observability and stall detection to the Phoenix implementation.

**Architecture:** Extend orchestrator running entries with Codex runtime fields, update those fields
from `{:codex_update, issue_id, message}` messages, and expose them through the existing snapshot
API. Keep token/rate-limit extraction in small helpers so later Codex protocol variants can be added
without changing scheduling logic.

**Tech Stack:** Elixir 1.19 / OTP 28, GenServer, ExUnit.

---

## Tasks

- [x] Add orchestrator tests for runner `on_message` callback wiring and snapshot event metadata.
- [x] Add orchestrator tests for token totals and rate-limit aggregation.
- [x] Add orchestrator tests for stall detection and retry scheduling.
- [x] Implement Codex update handling in `Symphony.Orchestrator`.
- [x] Extend `Symphony.Orchestrator.State` snapshot fields.
- [x] Update README, task plan, and progress notes.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 6.
