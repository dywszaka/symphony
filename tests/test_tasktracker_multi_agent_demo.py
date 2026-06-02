import importlib.util
import pathlib
import unittest
from unittest import mock


SCRIPT_PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "tasktracker_multi_agent_demo.py"
SPEC = importlib.util.spec_from_file_location("tasktracker_multi_agent_demo", SCRIPT_PATH)
demo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(demo)


class TaskTrackerMultiAgentDemoTest(unittest.TestCase):
    def test_operation_delay_sleeps_between_default_bounds(self):
        with mock.patch.object(demo.time, "sleep") as sleep:
            demo.operation_delay(random_func=lambda start, end: 12.5)

        sleep.assert_called_once_with(12.5)

    def test_operation_delay_rejects_out_of_bounds_random_values(self):
        with self.assertRaises(AssertionError):
            demo.operation_delay(random_func=lambda start, end: 25)

    def test_maybe_add_progress_comment_randomly_writes_comment(self):
        calls = []

        def fake_request(method, path, payload=None, query=None):
            calls.append((method, path, payload, query))

        task = {"id": "task-1", "identifier": "DEMO-1"}

        posted = demo.maybe_add_progress_comment(
            "agent-alpha",
            task,
            "after claim",
            chance_func=lambda: 0.1,
            request_func=fake_request,
        )

        self.assertTrue(posted)
        self.assertEqual(calls[0][0], "POST")
        self.assertEqual(calls[0][1], "/tasks/task-1/comments")
        self.assertEqual(calls[0][2]["author"], "agent-alpha")
        self.assertIn("DEMO-1", calls[0][2]["body"])
        self.assertIn("after claim", calls[0][2]["body"])

    def test_maybe_add_progress_comment_can_skip_comment(self):
        calls = []

        posted = demo.maybe_add_progress_comment(
            "agent-alpha",
            {"id": "task-1", "identifier": "DEMO-1"},
            "before completion",
            chance_func=lambda: 0.99,
            request_func=lambda *args, **kwargs: calls.append(args),
        )

        self.assertFalse(posted)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
