# Symphony Phoenix Phase 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add startup cleanup and deterministic local end-to-end validation.

**Architecture:** Extend orchestrator initialization with a best-effort startup cleanup pass that
uses the tracker and workspace modules already implemented. Add one E2E-style ExUnit test that runs
the orchestrator with memory/fake dependencies and verifies dispatch, Codex event accounting, and
retry behavior together.

**Tech Stack:** Elixir 1.19 / OTP 28, GenServer, ExUnit.

---

## Tasks

- [x] Add tests for startup terminal workspace cleanup and non-fatal cleanup errors.
- [x] Implement startup cleanup in `Symphony.Orchestrator`.
- [x] Add deterministic local E2E orchestration test.
- [x] Update README, task plan, and progress notes.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 7.
