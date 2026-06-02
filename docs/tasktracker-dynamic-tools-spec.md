# TaskTracker Dynamic Tools Spec

This document defines the TaskTracker write surface Symphony exposes to Codex dynamic tools.

## REST API Contract

TaskTracker must support these authenticated endpoints. Requests use the same bearer token as the
read API.

### Create Comment

- Method: `POST`
- Path: `/tasks/:task_id/comments`
- JSON body: `{"author": "symphony", "body": "<comment text>"}`
- Success: any `2xx` response

### Update State

- Method: `PATCH`
- Path: `/tasks/:task_id/state`
- JSON body: `{"actor": "symphony", "state": "<state name>"}`
- Success: any `2xx` response

### Update Workpad

- Method: `PATCH`
- Path: `/tasks/:task_id/workpad`
- JSON body: `{"actor": "symphony", "body": "<workpad markdown/text>"}`
- Success: any `2xx` response

## Dynamic Tool Contract

Symphony exposes these Codex client-side tools:

- `tasktracker_create_comment`
  - Required arguments: `issue_id`, `body`
- `tasktracker_update_state`
  - Required arguments: `issue_id`, `state`
- `tasktracker_update_workpad`
  - Required arguments: `issue_id`, `body`

All required arguments must be non-empty strings. Successful calls return a dynamic tool result with
`success: true` and a JSON output body of `{"ok": true}`. Validation and tracker failures return
`success: false` with a structured JSON error.
