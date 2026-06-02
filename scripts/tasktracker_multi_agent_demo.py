#!/usr/bin/env python3
"""
Seed TaskTracker and simulate several agents pulling work from it.

This demo intentionally does not launch Codex or any real agent runtime. It uses
TaskTracker HTTP calls to show the tracker-side flow that Symphony now supports.
"""

from __future__ import annotations

import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


BASE_URL = os.environ.get("TASKTRACKER_URL", "http://127.0.0.1:4001").rstrip("/")
TOKEN = os.environ.get("TASKTRACKER_TOKEN", "dev-token")
PROJECT_KEY = os.environ.get("TASKTRACKER_PROJECT", "symphony-demo")
DELAY_MIN_SECONDS = float(os.environ.get("TASKTRACKER_DEMO_DELAY_MIN", "10"))
DELAY_MAX_SECONDS = float(os.environ.get("TASKTRACKER_DEMO_DELAY_MAX", "20"))
COMMENT_PROBABILITY = float(os.environ.get("TASKTRACKER_DEMO_COMMENT_PROBABILITY", "0.5"))
AGENTS = ["agent-alpha", "agent-beta", "agent-gamma"]
TASK_TITLES = [
    "Add TaskTracker adapter",
    "Replace Linear workflow config",
    "Render tracker status in dashboard",
    "Document local tracker setup",
    "Verify blocked task behavior",
    "Exercise continuation polling",
]
COMMENT_TEMPLATES = [
    "{agent} checked tracker state for {identifier} during {stage}.",
    "{agent} recorded simulated progress on {identifier} during {stage}.",
    "{agent} noted that {identifier} is still moving through the demo flow during {stage}.",
    "{agent} added an audit breadcrumb for {identifier} during {stage}.",
]

claimed = set()


class ApiError(RuntimeError):
    pass


def api_url(path: str, query: dict[str, str] | None = None) -> str:
    url = f"{BASE_URL}/api/v1{path}"
    if query:
        return f"{url}?{urllib.parse.urlencode(query)}"
    return url


def request(method: str, path: str, payload: dict | None = None, query: dict[str, str] | None = None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"

    req = urllib.request.Request(api_url(path, query), data=body, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            raw_body = response.read()
            if not raw_body:
                return None
            return json.loads(raw_body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw_body = exc.read().decode("utf-8", errors="replace")
        try:
            error = json.loads(raw_body)
        except json.JSONDecodeError:
            error = raw_body
        raise ApiError(f"{method} {path} failed with {exc.code}: {error}") from exc
    except urllib.error.URLError as exc:
        raise ApiError(f"TaskTracker is not reachable at {BASE_URL}: {exc.reason}") from exc


def operation_delay(
    label: str | None = None,
    random_func=random.uniform,
    sleep_func=None,
) -> float:
    sleep_func = sleep_func or time.sleep
    seconds = random_func(DELAY_MIN_SECONDS, DELAY_MAX_SECONDS)
    assert DELAY_MIN_SECONDS <= seconds <= DELAY_MAX_SECONDS

    if seconds > 0:
        if label:
            print(f"waiting {seconds:.1f}s before {label}")
        sleep_func(seconds)

    return seconds


def maybe_add_progress_comment(
    agent_name: str,
    task: dict,
    stage: str,
    chance_func=random.random,
    choice_func=random.choice,
    request_func=request,
) -> bool:
    if chance_func() >= COMMENT_PROBABILITY:
        return False

    body = choice_func(COMMENT_TEMPLATES).format(
        agent=agent_name,
        identifier=task["identifier"],
        stage=stage,
    )

    request_func(
        "POST",
        f"/tasks/{urllib.parse.quote(task['id'])}/comments",
        {
            "author": agent_name,
            "body": body,
        },
    )
    print(f"{agent_name}: added comment on {task['identifier']} ({stage})")
    return True


def ensure_server() -> None:
    try:
        with urllib.request.urlopen(f"{BASE_URL}/health", timeout=3) as response:
            if response.status != 200:
                raise ApiError(f"TaskTracker health check returned {response.status}")
    except urllib.error.URLError as exc:
        raise ApiError(
            "TaskTracker is not running. Start it with:\n"
            "  TASKTRACKER_TOKEN=dev-token "
            "python3 -m tasktracker.app --db tasktracker-demo.db --port 4001"
        ) from exc


def ensure_project() -> None:
    payload = {
        "key": PROJECT_KEY,
        "name": "Symphony Demo",
        "description": "Demo project for simulated multi-agent dispatch.",
    }

    try:
        request("POST", "/projects", payload)
        print(f"created project {PROJECT_KEY}")
    except ApiError as exc:
        if "project key already exists" not in str(exc):
            raise
        print(f"using existing project {PROJECT_KEY}")


def seed_tasks() -> None:
    for index, title in enumerate(TASK_TITLES, start=1):
        payload = {
            "title": title,
            "description": f"Demo task #{index}; no real agent will run.",
            "state": "Todo",
            "priority": (index % 4) + 1,
            "labels": ["demo", "symphony"],
            "actor": "demo-script",
        }

        task = request("POST", f"/projects/{urllib.parse.quote(PROJECT_KEY)}/tasks", payload)
        print(f"seeded {task['identifier']}: {task['title']}")


def fetch_todo_tasks() -> list[dict]:
    response = request(
        "GET",
        f"/projects/{urllib.parse.quote(PROJECT_KEY)}/tasks",
        query={"state": "Todo", "limit": "100"},
    )
    return response["data"]


def claim_next_task() -> dict | None:
    for task in fetch_todo_tasks():
        if task["id"] in claimed:
            continue

        claimed.add(task["id"])
        operation_delay(f"claiming {task['identifier']}")

        request(
            "PATCH",
            f"/tasks/{urllib.parse.quote(task['id'])}/state",
            {"state": "In Progress", "actor": "demo-dispatcher"},
        )
        return task

    return None


def agent_step(agent_name: str) -> bool:
    task = claim_next_task()
    if task is None:
        return False

    identifier = task["identifier"]
    print(f"{agent_name}: claimed {identifier} - {task['title']}")

    operation_delay(f"{agent_name} progress check for {identifier}")
    maybe_add_progress_comment(agent_name, task, "after claim")

    operation_delay(f"{agent_name} completion update for {identifier}")
    maybe_add_progress_comment(agent_name, task, "before completion")

    request(
        "PATCH",
        f"/tasks/{urllib.parse.quote(task['id'])}/state",
        {"state": "Done", "actor": agent_name},
    )

    operation_delay(f"{agent_name} post-completion audit for {identifier}")
    maybe_add_progress_comment(agent_name, task, "after completion")

    print(f"{agent_name}: completed {identifier}")
    return True


def run_scheduler() -> None:
    while True:
        progressed = False

        for agent_name in AGENTS:
            if agent_step(agent_name):
                progressed = True

        if not progressed:
            for agent_name in AGENTS:
                print(f"{agent_name}: no Todo tasks left")
            return


def main() -> int:
    try:
        ensure_server()
        ensure_project()
        seed_tasks()

        print("")
        print(f"simulating {len(AGENTS)} agents against {BASE_URL}/projects/{PROJECT_KEY}/tasks")

        run_scheduler()

        print("")
        print("demo complete")
        return 0
    except ApiError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
