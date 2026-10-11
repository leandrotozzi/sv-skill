"""PostToolUse hook: after a .sv/.svh edit, hand svstyle's verdict to the model.

Fast checks only (`--no-external`); silent when svstyle is missing or the file is
clean, and never blocks: the full `check --synth` is still the skill's job.
"""

import json
import shutil
import subprocess
import sys

path = json.load(sys.stdin).get("tool_input", {}).get("file_path", "")
exe = shutil.which("svstyle")
if not path.endswith((".sv", ".svh")) or exe is None:
    sys.exit(0)
try:
    res = subprocess.run([exe, "check", "--no-external", path],
                         capture_output=True, text=True, timeout=25)  # fmt: skip
except subprocess.TimeoutExpired:
    sys.exit(0)
if res.returncode == 0:
    sys.exit(0)
lines = (res.stdout + res.stderr).strip().splitlines()
note = f"svstyle check --no-external {path} exited {res.returncode}:\n" + "\n".join(lines[-15:])
out = {"hookEventName": "PostToolUse", "additionalContext": note}
print(json.dumps({"hookSpecificOutput": out}))
