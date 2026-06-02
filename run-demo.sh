#!/usr/bin/env sh
set -eu

TASKTRACKER_DEMO_DELAY_MIN=5 \
TASKTRACKER_DEMO_DELAY_MAX=20 \
TASKTRACKER_DEMO_COMMENT_PROBABILITY=0.9 \
TASKTRACKER_URL=http://127.0.0.1:4001 \
TASKTRACKER_TOKEN=dev-token \
TASKTRACKER_PROJECT=symphony-demo \
python3 scripts/tasktracker_multi_agent_demo.py
