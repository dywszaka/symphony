# Symphony Phoenix Phase 3 Design

## Goal

Add a Linear-compatible tracker adapter for the Phoenix implementation, covering the required
tracker read operations from `SPEC.md` without integrating Codex or tracker writes.

## Scope

- GraphQL request client with configured endpoint and bearer token.
- Candidate issue query filtered by `project.slugId` and configured active states.
- Pagination for candidate issue fetches.
- Issue lookup by GraphQL IDs with `[ID!]` variable typing.
- Issue fetch by state names for startup cleanup.
- Normalization into `Symphony.Tracker.Issue`.
- Error mapping for request failures, non-200 responses, GraphQL errors, malformed payloads, and
  missing pagination cursors.

## Out of Scope

- Tracker writes.
- `linear_graphql` dynamic tool.
- Codex app-server integration.
- Live Linear end-to-end tests.

## Testing

All Phase 3 tests use mocked HTTP functions. No test calls the real Linear API.

