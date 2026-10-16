#!/usr/bin/env python3
"""Paired complete-app default-page memory measurement on an ephemeral CI Mac.

Does not measure all-page GUI interactions, sustained power, or a 10x target.
Each arm uses a fresh private home, no hooks, and the same visible default page.
Only the exact app process launched by this harness is stopped.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import statistics
import subprocess
import time
import urllib.request
import shutil

ROOT = Path(__file__).resolve().parent.parent
RELEASES = {
    "baseline": ("0.2.15", 20, "cd1634b440db023c58de8212934c7866de1c46ca334e3cf7b6d5b7bc412cd948"),
    "candidate": ("0.2.20", 25, "cc7b6e68600f84fefcdff54d39d6eaf5719ecfe4037b8c98386f882aed51f551"),
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=180, **kwargs).stdout


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.uname().sysname != "Darwin":
        raise RuntimeError("Run only on an ephemeral GitHub macOS runner; never change an owner's launch environment")
    out = Path(os.environ["RUNNER_TEMP"]) / "performancedaddy-memory"
    out.mkdir()
    report = {"scope": "complete published app, visible default Processes page, no agent hooks or owner data",
              "os": run("sw_vers"), "architecture": run("uname", "-m").strip(),
              "cpu": run("sysctl", "-n", "machdep.cpu.brand_string").strip(),
              "warmupSeconds": 15, "sampleCountPerArm": 10, "sampleIntervalSeconds": 2,
              "limitations": ["Default-page workload only; not all-page interaction or original warm owner workload",
                              "RSS and physical footprint are process memory, not energy",
                              "Fresh private homes and the same runner reduce state differences; host inventory may still vary"],
              "arms": []}
    def save():
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    save()
    try:
        probe = out / "probe"
        run("cc", str(ROOT / "scripts/complete-app-probe.c"), "-framework", "ApplicationServices", "-o", str(probe))
        # Install a pinned automation tool outside the product dependency graph.
        tool = out / "tools"
        run("npm", "install", "--prefix", str(tool), "--no-audit", "--no-fund", "xcodebuildmcp@2.7.0")
        cli = tool / "node_modules/xcodebuildmcp/build/cli.js"
        apps = {}
        for label, (version, build, digest) in RELEASES.items():
            dmg = out / f"{label}.dmg"
            url = f"https://github.com/Significant-Hobbies/performancedaddy/releases/download/v{version}-{build}/performancedaddy-{version}-build{build}-universal.dmg"
            urllib.request.urlretrieve(url, dmg)
            if hashlib.sha256(dmg.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"{label}: published DMG digest mismatch")
            mounted = plistlib.loads(subprocess.check_output(["hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg)]))
            volumes = [Path(e["mount-point"]) for e in mounted["system-entities"] if "mount-point" in e]
            if len(volumes) != 1:
                raise RuntimeError(f"{label}: ambiguous DMG mount")
            try:
                app = out / label / "PerformanceDaddy.app"
                shutil.copytree(volumes[0] / "PerformanceDaddy.app", app, symlinks=True)
            finally:
                run("hdiutil", "detach", str(volumes[0]))
            run("codesign", "--verify", "--deep", "--strict", str(app))
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            if str(info["CFBundleVersion"]) != str(build):
                raise RuntimeError(f"{label}: wrong bundle build")
            apps[label] = app
        for index, label in enumerate(["baseline", "candidate", "candidate", "baseline", "baseline", "candidate"]):
            app = apps[label]
            arm = {"index": index, "label": label, "dmgSha256": RELEASES[label][2], "samples": []}
            report["arms"].append(arm)
            home = out / f"home-{index}"
            home.mkdir()
            pid = None
            try:
                run("launchctl", "setenv", "CFFIXED_USER_HOME", str(home))
                arm["launch"] = run("node", str(cli), "macos", "launch", "--app-path", str(app), "--output", "json")
                # Match the full executable path, not a reusable PID or bundle id.
                executable = str(app / "Contents/MacOS/PerformanceDaddy")
                for _ in range(20):
                    rows = run("ps", "-axo", "pid=,comm=").splitlines()
                    matches = [int(row.split(None, 1)[0]) for row in rows if len(row.split(None, 1)) == 2 and row.split(None, 1)[1] == executable]
                    if len(matches) == 1:
                        pid = matches[0]
                        break
                    time.sleep(0.5)
                if pid is None:
                    raise RuntimeError(f"{label}: exact published app did not stay running")
                arm["pid"] = pid
                time.sleep(report["warmupSeconds"])
                identity = None
                for _ in range(report["sampleCountPerArm"]):
                    sample = json.loads(run(str(probe), str(pid)))
                    if not sample["visibleWindows"]:
                        raise RuntimeError(f"{label}: no visible main window; refusing a headless-memory claim")
                    if identity is not None and sample["startIdentity"] != identity:
                        raise RuntimeError("PID identity changed during measurement")
                    identity = sample["startIdentity"]
                    sample["monotonicSeconds"] = time.monotonic()
                    sample["hostProcessCount"] = len(run("ps", "-axo", "pid=").splitlines())
                    arm["samples"].append(sample)
                    save()
                    time.sleep(report["sampleIntervalSeconds"])
                arm["privateHomeEntries"] = sorted(p.name for p in home.iterdir())
                for metric in ["residentBytes", "physicalFootprintBytes"]:
                    arm[metric] = statistics.median(s[metric] for s in arm["samples"])
            finally:
                if pid is not None:
                    # Verify this remains the app we launched before asking MCP to stop it.
                    if run("ps", "-p", str(pid), "-o", "comm=").strip() == str(app / "Contents/MacOS/PerformanceDaddy"):
                        run("node", str(cli), "macos", "stop", "--process-id", str(pid), "--output", "json")
                run("launchctl", "unsetenv", "CFFIXED_USER_HOME")
                save()
        report["summary"] = {}
        for metric in ["residentBytes", "physicalFootprintBytes"]:
            baseline = statistics.median(a[metric] for a in report["arms"] if a["label"] == "baseline")
            candidate = statistics.median(a[metric] for a in report["arms"] if a["label"] == "candidate")
            report["summary"][metric] = {"baselineMedian": baseline, "candidateMedian": candidate,
                                          "candidateOverBaseline": candidate / baseline}
        report["result"] = "measured"
    except Exception as error:
        report["result"] = "unavailable"
        report["error"] = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            report["commandStdout"] = error.stdout
            report["commandStderr"] = error.stderr
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
