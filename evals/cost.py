"""Cost and time of each eval run, from the eval subagents' Claude Code transcripts.

    uv run python evals/cost.py skill/systemverilog-rtl-workspace/<iteration> [TRANSCRIPT_DIR...]

A transcript belongs to a run when its first prompt names the run's
`<eval>/<config>/[run-N/]outputs` path. Writes `<eval>/<config>/run-N/cost.json`
(run-1 when the path has no run).
Input and cache cost are exact; output (incl. thinking) is an estimate.
TRANSCRIPT_DIR defaults to every `*/subagents` of this project's sessions.
"""

import json
import re
import sys
from datetime import datetime
from pathlib import Path

# USD per million tokens, Claude Opus 5.5 (cache writes: 5 min x1.25, 1 h x2).
PRICE = {"input": 4.0, "cache_5m": 5.0, "cache_1h": 8.0, "cache_read": 0.2, "output": 20.0}
PROJECT = Path.home() / ".claude/projects/-Users-leandrotozzi-Documents-claude-sv-skill"


def _chars(x) -> int:
    return len(x) if isinstance(x, str) else len(json.dumps(x))


def run_cost(lines: list[dict]) -> dict:
    """Claude Code logs each message's usage when it starts streaming, so input
    and cache counts are exact but `output_tokens` is a stub. Output (thinking
    included) is estimated from how much the context grows by the next turn,
    minus that turn's tool results; a message without thinking counts its
    visible text and tool input. Characters / 3.5 approximate tokens."""
    msgs: list[dict] = []
    checks = 0  # `svstyle check` runs: 1 means the style closed in one pass
    for d in lines:
        if d.get("type") == "assistant" and "usage" in d.get("message", {}):
            m = d["message"]
            if not msgs or msgs[-1]["id"] != m["id"]:
                msgs.append({"id": m["id"], "usage": m["usage"], "vis": 0, "think": False, "tr": 0})
            for b in m["content"]:
                if b["type"] == "thinking":
                    msgs[-1]["think"] = True
                elif b["type"] == "text":
                    msgs[-1]["vis"] += len(b["text"])
                elif b["type"] == "tool_use":
                    msgs[-1]["vis"] += _chars(b["input"])
                    checks += "svstyle check" in str(b["input"].get("command", ""))
        elif d.get("type") == "user" and msgs and isinstance(d["message"]["content"], list):
            for b in d["message"]["content"]:
                if b.get("type") == "tool_result":
                    msgs[-1]["tr"] += _chars(b.get("content", ""))
    tok = dict.fromkeys(PRICE, 0)
    ctx = []
    for msg in msgs:
        u = msg["usage"]
        cc = u.get("cache_creation") or {}
        flat = u.get("cache_creation_input_tokens", 0)
        tok["input"] += u.get("input_tokens", 0)
        tok["cache_5m"] += cc.get("ephemeral_5m_input_tokens", flat)
        tok["cache_1h"] += cc.get("ephemeral_1h_input_tokens", 0)
        tok["cache_read"] += u.get("cache_read_input_tokens", 0)
        ctx.append(u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + flat)
    for i, msg in enumerate(msgs):
        vis = round(msg["vis"] / 3.5)
        grown = ctx[i + 1] - ctx[i] - round(msg["tr"] / 3.5) if i + 1 < len(msgs) else 0
        tok["output"] += max(vis, grown) if msg["think"] else vis
    stamps = [datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
              for d in lines if "timestamp" in d]  # fmt: skip
    wall = (max(stamps) - min(stamps)).total_seconds() if stamps else 0.0
    return {
        "turns": len(msgs),
        "svstyle_checks": checks,
        "tokens": tok,
        "usd": round(sum(tok[k] * PRICE[k] for k in PRICE) / 1e6, 4),
        "usd_output": round(tok["output"] * PRICE["output"] / 1e6, 4),
        "wall_s": round(wall, 1),
    }


def first_prompt(lines: list[dict]) -> str:
    for d in lines:
        if d.get("type") == "user":
            c = d["message"]["content"]
            return c if isinstance(c, str) else " ".join(b.get("text", "") for b in c)
    return ""


def main(iteration: Path, dirs: list[Path]) -> None:
    files = [f for d in dirs for f in d.glob("*.jsonl")]
    cfg = r"/(eval-[\w-]+)/(with_skill|without_skill)/(run-\d+/)?outputs"
    pat = re.compile(re.escape(iteration.name) + cfg)
    for f in files:
        lines = [json.loads(ln) for ln in f.read_text().splitlines() if ln.strip()]
        m = pat.search(first_prompt(lines))
        if not m:
            continue
        run = iteration / m[1] / m[2] / (m[3] or "run-1/").rstrip("/")
        run.mkdir(parents=True, exist_ok=True)
        cost = {**run_cost(lines), "transcript": str(f)}
        (run / "cost.json").write_text(json.dumps(cost, indent=2))
        c = cost
        print(
            f"{m[1]:28} {m[2]:14} {run.name:6} ${c['usd']:7.3f} {c['wall_s']:7.0f}s"
            f" {c['turns']:4} turns"
        )


if __name__ == "__main__":
    it = Path(sys.argv[1]).resolve()
    main(it, [Path(p) for p in sys.argv[2:]] or sorted(PROJECT.glob("*/subagents")))
