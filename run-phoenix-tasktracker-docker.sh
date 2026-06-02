#!/usr/bin/env sh
set -eu

# Fill these values before running.
TASKTRACKER_ENDPOINT="${TASKTRACKER_ENDPOINT:-http://host.docker.internal:4001/api/v1}"
TASKTRACKER_TOKEN="${TASKTRACKER_TOKEN:-}"
TASKTRACKER_PROJECT_KEY="${TASKTRACKER_PROJECT_KEY:-}"

# Task selection.
TASKTRACKER_ACTIVE_STATES="${TASKTRACKER_ACTIVE_STATES:-Todo,In Progress}"
TASKTRACKER_TERMINAL_STATES="${TASKTRACKER_TERMINAL_STATES:-Done,Canceled}"

# Symphony runtime.
HTTP_PORT="${HTTP_PORT:-4002}"
POLLING_INTERVAL_MS="${POLLING_INTERVAL_MS:-30000}"
MAX_CONCURRENT_AGENTS="${MAX_CONCURRENT_AGENTS:-2}"
MAX_TURNS="${MAX_TURNS:-20}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/app/.symphony-tasktracker-runtime/workspaces}"

# The Docker image must contain Elixir/Mix and the command below must be available inside it.
# Use a custom image here if you need Codex preinstalled.
SYMPHONY_IMAGE="${SYMPHONY_IMAGE:-elixir:1.19.5-otp-28-alpine}"
CODEX_COMMAND="${CODEX_COMMAND:-codex app-server}"
DRY_RUN="${DRY_RUN:-0}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNTIME_DIR="${SCRIPT_DIR}/.symphony-tasktracker-runtime"
WORKFLOW_FILE="${RUNTIME_DIR}/WORKFLOW.tasktracker.md"
MIX_CACHE_DIR="${SCRIPT_DIR}/.docker_mix"

require_value() {
  name="$1"
  value="$2"

  if [ -z "$value" ]; then
    echo "Missing required config: $name" >&2
    echo "Edit $0 or pass $name=... before running." >&2
    exit 1
  fi
}

yaml_list() {
  values="$1"
  old_ifs="$IFS"
  IFS=,

  for item in $values; do
    trimmed=$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ -n "$trimmed" ]; then
      printf '    - %s\n' "$trimmed"
    fi
  done

  IFS="$old_ifs"
}

require_value "TASKTRACKER_TOKEN" "$TASKTRACKER_TOKEN"
require_value "TASKTRACKER_PROJECT_KEY" "$TASKTRACKER_PROJECT_KEY"

mkdir -p "$RUNTIME_DIR" "$MIX_CACHE_DIR" "${SCRIPT_DIR}/.symphony-tasktracker-runtime/workspaces"

{
  cat <<EOF
---
tracker:
  kind: tasktracker
  endpoint: ${TASKTRACKER_ENDPOINT}
  project_key: ${TASKTRACKER_PROJECT_KEY}
  api_key: \$TASKTRACKER_TOKEN
  active_states:
EOF
  yaml_list "$TASKTRACKER_ACTIVE_STATES"
  cat <<EOF
  terminal_states:
EOF
  yaml_list "$TASKTRACKER_TERMINAL_STATES"
  cat <<EOF
workspace:
  root: ${WORKSPACE_ROOT}
polling:
  interval_ms: ${POLLING_INTERVAL_MS}
agent:
  max_concurrent_agents: ${MAX_CONCURRENT_AGENTS}
  max_turns: ${MAX_TURNS}
codex:
  command: ${CODEX_COMMAND}
---

You are working on a tracker task.

Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
URL: {{ issue.url }}
State: {{ issue.state }}
Priority: {{ issue.priority }}
Labels: {{ issue.labels }}

Description:
{{ issue.description }}
EOF
} > "$WORKFLOW_FILE"

echo "Starting Symphony Phoenix with TaskTracker workflow:"
echo "  workflow: $WORKFLOW_FILE"
echo "  endpoint: $TASKTRACKER_ENDPOINT"
echo "  project:  $TASKTRACKER_PROJECT_KEY"
echo "  port:     $HTTP_PORT"
echo
echo "Health:  http://127.0.0.1:${HTTP_PORT}/health"
echo "State:   http://127.0.0.1:${HTTP_PORT}/api/v1/state"
echo "Refresh: curl -X POST http://127.0.0.1:${HTTP_PORT}/api/v1/refresh"
echo

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1, not starting Docker."
  exit 0
fi

docker run --rm \
  -u "$(id -u):$(id -g)" \
  --add-host=host.docker.internal:host-gateway \
  -e HOME=/tmp \
  -e TASKTRACKER_TOKEN="$TASKTRACKER_TOKEN" \
  -e WORKFLOW_PATH=/app/.symphony-tasktracker-runtime/WORKFLOW.tasktracker.md \
  -p "${HTTP_PORT}:4002" \
  -v "$MIX_CACHE_DIR":/tmp/.mix \
  -v "$SCRIPT_DIR":/app \
  -w /app/phoenix \
  "$SYMPHONY_IMAGE" \
  sh -lc 'mix local.hex --force >/dev/null && mix deps.get && mix run --no-start -e '\''config = Application.get_env(:symphony, SymphonyWeb.Endpoint, []); Application.put_env(:symphony, SymphonyWeb.Endpoint, Keyword.merge(config, http: [ip: {0, 0, 0, 0}, port: 4002], server: true, secret_key_base: String.duplicate("a", 64))); Application.ensure_all_started(:symphony); Process.sleep(:infinity)'\'''
