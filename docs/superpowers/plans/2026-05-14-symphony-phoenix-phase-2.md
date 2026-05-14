# Symphony Phoenix Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement scheduler dispatch, eligibility, retry, and reconciliation semantics in the Phoenix/OTP implementation without Linear or Codex integration.

**Architecture:** `Symphony.Orchestrator` remains the only writer of scheduler state. Tracker and runner modules are injectable for tests; memory tracker and fake runner drive deterministic behavior. Public helpers expose pure sorting/eligibility calculations for focused unit tests.

**Tech Stack:** Elixir 1.19 / OTP 28, GenServer, ExUnit, Phoenix/Bandit already present from Phase 1.

---

## Task 1: Tracker and Runner Injection

**Files:**
- Modify: `phoenix/lib/symphony/tracker/memory.ex`
- Create: `phoenix/lib/symphony/runner/behaviour.ex`
- Create: `phoenix/test/support/fake_runner.exs`
- Modify: `phoenix/test/test_helper.exs`

- [x] Add memory tracker reset and issue mutation helpers.
- [x] Add `Symphony.Runner.Behaviour`.
- [x] Add `Symphony.Support.FakeRunner` for tests.
- [x] Verify fake runner tests through later orchestrator tests.

## Task 2: Pure Scheduling Rules

**Files:**
- Create: `phoenix/test/symphony/orchestrator/scheduling_test.exs`
- Create: `phoenix/lib/symphony/orchestrator/scheduling.ex`

- [x] Write failing tests for sorting priority, created time, identifier tie-break.
- [x] Write failing tests for active/terminal/claimed/running/blocker eligibility.
- [x] Implement `Symphony.Orchestrator.Scheduling`.
- [x] Run focused scheduling tests.

## Task 3: Dispatch and Concurrency

**Files:**
- Modify: `phoenix/test/symphony/orchestrator_test.exs`
- Modify: `phoenix/lib/symphony/orchestrator.ex`
- Modify: `phoenix/lib/symphony/orchestrator/state.ex`

- [x] Write failing tests for dispatching eligible memory issues.
- [x] Write failing tests for global and per-state concurrency.
- [x] Implement `dispatch_once/1`, claim tracking, running entries, and snapshot expansion.
- [x] Run orchestrator tests.

## Task 4: Completion and Retry

**Files:**
- Modify: `phoenix/test/symphony/orchestrator_test.exs`
- Modify: `phoenix/lib/symphony/orchestrator.ex`
- Modify: `phoenix/lib/symphony/orchestrator/state.ex`

- [x] Write failing tests for normal worker exit scheduling continuation retry.
- [x] Write failing tests for abnormal worker exit scheduling exponential backoff.
- [x] Write failing tests for retry release when issue is absent from candidates.
- [x] Implement monitor handling, retry entry creation, and retry timer handling.
- [x] Run orchestrator tests.

## Task 5: Reconciliation

**Files:**
- Modify: `phoenix/test/symphony/orchestrator_test.exs`
- Modify: `phoenix/lib/symphony/orchestrator.ex`

- [x] Write failing tests for terminal issue reconciliation.
- [x] Write failing tests for non-active/non-terminal issue reconciliation.
- [x] Write failing tests for active issue snapshot refresh.
- [x] Implement `reconcile_once/1`.
- [x] Run orchestrator tests.

## Task 6: Verification and Commit

**Files:**
- Modify: `task_plan.md`
- Modify: `progress.md`
- Modify: `phoenix/README.md` if usage changed materially.

- [x] Run `mix format`.
- [x] Run `mix test`.
- [x] Update tracking docs.
- [x] Commit Phase 2.

