# Symphony Phoenix Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Linear tracker adapter required by `SPEC.md`.

**Architecture:** Add `Symphony.Linear.Client` for GraphQL transport and `Symphony.Linear.Adapter` for query construction, pagination, error mapping, and issue normalization. Tests inject a fake HTTP post function so no real Linear API calls occur.

**Tech Stack:** Elixir 1.19 / OTP 28, Jason, ExUnit.

---

## Tasks

- [x] Add Linear adapter tests for candidate pagination, query semantics, and normalization.
- [x] Add tests for issue state refresh query using `[ID!]`.
- [x] Add tests for `fetch_issues_by_states/2`.
- [x] Add tests for request, status, GraphQL, malformed payload, and missing cursor errors.
- [x] Implement `Symphony.Linear.Client`.
- [x] Implement `Symphony.Linear.Adapter`.
- [x] Update docs/status.
- [x] Run `mix format` and `mix test`.
- [x] Commit Phase 3.
