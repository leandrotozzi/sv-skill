"""evals/cost.py: usage counted once per streamed message, priced for Opus 5.5."""

import importlib.util
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("cost", Path(__file__).parents[1] / "evals/cost.py")
cost = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cost)


def _msg(mid, ts, ctx, content):
    usage = {"input_tokens": 10, "cache_read_input_tokens": ctx - 110, "output_tokens": 1,
             "cache_creation_input_tokens": 100,
             "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 0}}
    return {"type": "assistant", "timestamp": ts,
            "message": {"id": mid, "usage": usage, "content": content}}


def _result(chars):
    return {"type": "user", "timestamp": "2026-10-05T10:00:30Z",
            "message": {"content": [{"type": "tool_result", "content": "x" * chars}]}}


def test_streamed_message_counted_once_and_output_estimated():
    think = {"type": "thinking", "thinking": "", "signature": "s"}
    tool = {"type": "tool_use", "input": {"cmd": "y" * 33}}  # 45 chars of JSON
    lines = [
        {"type": "user", "timestamp": "2026-10-05T10:00:00Z", "message": {"content": "go"}},
        _msg("a", "2026-10-05T10:00:05Z", 1000, [think]),
        _msg("a", "2026-10-05T10:00:06Z", 1000, [tool]),
        _result(350),  # ~100 tokens
        _msg("b", "2026-10-05T10:01:00Z", 1600, [{"type": "text", "text": "z" * 70}]),
    ]
    c = cost.run_cost(lines)
    assert c["turns"] == 2
    # a: thinking, so context growth 600 minus 100 of tool result; b: last, visible 20
    assert c["tokens"]["output"] == 500 + 20
    assert c["tokens"]["cache_read"] == 890 + 1490
    assert c["wall_s"] == 60.0
