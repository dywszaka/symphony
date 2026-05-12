# Findings

## Repository Context

- The repository contains `SPEC.md`, which defines Symphony as a long-running scheduler/runner for coding agents.
- Existing `elixir/` implementation is a reference only for this project. New work must live in a separate directory and follow the spec as the source of truth.
- The preferred stack is Elixir/OTP + Phoenix.

## Architecture Notes

- The core scheduler should be OTP-first and Phoenix-independent.
- Phoenix should expose observability surfaces such as health/state JSON endpoints and later an optional dashboard.
- A memory tracker is useful for deterministic tests and Phase 1 validation before Linear/Codex integration.

## Confirmed Decisions

- Use a new directory.
- Develop in phases.
- Test, commit, and pause for user confirmation after each phase.

