# Symphony Phoenix Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Codex app-server runner for the Phoenix implementation.

**Architecture:** Add a small prompt renderer, a focused stdio JSON-RPC app-server client, and a
runner module that bridges orchestrator issues to Codex turns. Tests fake the app-server and tracker
so Phase 4 remains deterministic and does not require live Codex credentials.

**Tech Stack:** Elixir 1.19 / OTP 28, Port stdio, Jason, ExUnit.

---

## Tasks

- [x] Add prompt template tests for successful issue/attempt rendering and strict unknown
      variable/filter failures.
- [x] Implement `Symphony.Prompt.Template`.
- [x] Add Codex app-server client tests for launch cwd, initialize/thread/turn requests,
      completion, approvals, unsupported tools, user-input failure, and timeout/error mapping.
- [x] Implement `Symphony.Codex.AppServer`.
- [x] Add runner tests for workspace creation, first prompt, continuation prompt, state refresh, and
      `agent.max_turns`.
- [x] Implement `Symphony.Runner.Codex`.
- [x] Update README, task plan, and progress notes.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 4.
