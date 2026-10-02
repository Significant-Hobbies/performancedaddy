#!/usr/bin/env python3
"""Run the opt-in native render probe in a fresh Release test process.

Copy NativeResourceProbeTests.swift to an isolated baseline checkout to compare
the same fixture. Measures test host + product views, not the installed app.
"""
import os
from pathlib import Path
import subprocess
import sys

repo = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
env = dict(os.environ, PERFORMANCEDADDY_RESOURCE_PROBE="1")
result = subprocess.run(
    ["swift", "test", "-c", "release", "--filter", "NativeResourceProbeTests/testRenderedProcessAndMemoryPagesFootprint"],
    cwd=repo, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
lines = [line for line in result.stdout.splitlines() if "NATIVE_RESOURCE_PROBE" in line]
if result.returncode or len(lines) != 5:
    print(result.stdout)
    sys.exit(result.returncode or 1)
print("\n".join(lines))
