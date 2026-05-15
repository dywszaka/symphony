# Symphony Phoenix Phase 8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement dynamic `WORKFLOW.md` reload semantics.

**Architecture:** Add `Symphony.Orchestrator.reconfigure/3` to apply parsed settings/prompt to the
running orchestrator. Add `Symphony.Workflow.Watcher`, a small GenServer that polls workflow mtime,
loads and validates settings, applies good reloads, and keeps operating with last-known-good state
on invalid reloads.

**Tech Stack:** Elixir 1.19 / OTP 28, GenServer, ExUnit.

---

## Tasks

- [x] Add orchestrator reconfigure tests for poll/concurrency/prompt updates.
- [x] Implement `Symphony.Orchestrator.reconfigure/3`.
- [x] Add workflow watcher tests for valid reload and invalid reload last-good behavior.
- [x] Implement `Symphony.Workflow.Watcher`.
- [x] Update README, task plan, and progress notes.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 8.
