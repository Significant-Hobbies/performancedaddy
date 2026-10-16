#!/usr/bin/env python3
"""Qualify exact published-app UI on an ephemeral Mac; --build-only never launches UI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
DMG_SHA256 = "cc7b6e68600f84fefcdff54d39d6eaf5719ecfe4037b8c98386f882aed51f551"
DMG_URL = ("https://github.com/Significant-Hobbies/performancedaddy/releases/download/"
           "v0.2.20-25/performancedaddy-0.2.20-build25-universal.dmg")
PAGES = ["Processes", "Ports", "Agent sessions", "Memory", "Fans & heat",
         "App access", "Configuration", "Diagnose"]


def run(*command, timeout=180, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True,
                          timeout=timeout, **kwargs).stdout


def mcp(cli, out, label, operation, arguments):
    command = ["node", str(cli), "macos", operation, "--json", json.dumps(arguments),
               "--output", "json"]
    result = subprocess.run(command, text=True, capture_output=True, timeout=900, cwd=ROOT)
    (out / f"{label}.stdout.json").write_text(result.stdout)
    (out / f"{label}.stderr.txt").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"{label}: XcodeBuildMCP exited {result.returncode}; see retained logs")
    payload = json.loads(result.stdout)
    if payload.get("didError") is not False:
        raise RuntimeError(f"{label}: missing successful structured XcodeBuildMCP result")
    return payload


def build_runner(cli, out):
    project = out / "project"
    project.mkdir()
    # XcodeGen resolves source paths relative to its output project directory.
    # Copy only this owned test source, never dependency or build directories.
    shutil.copyfile(ROOT / "Tests/PublishedAppUITests/PublishedAppUITests.swift",
                    project / "PublishedAppUITests.swift")
    run("xcodegen", "generate", "--spec", str(ROOT / "Tests/PublishedAppUITests/project.yml"),
        "--project", str(project))
    derived = out / "DerivedData"
    products = out / "PublishedUI.xctestproducts"
    result = mcp(cli, out, "build", "build", {
        "projectPath": str(project / "PerformanceDaddyPublishedUI.xcodeproj"),
        "scheme": "PublishedApp", "configuration": "Debug",
        "derivedDataPath": str(derived), "buildForTesting": True,
        "testProductsPath": str(products),
        "extraArgs": ["CODE_SIGNING_ALLOWED=NO"],
    })
    candidates = []
    for path in result.get("data", {}).get("artifacts", {}).get("xctestrunPaths", []):
        candidate = Path(path).expanduser()
        candidates.append((candidate if candidate.is_absolute() else ROOT / candidate).resolve())
    if len(candidates) != 1 or not candidates[0].is_relative_to(products):
        raise RuntimeError("Build did not produce exactly one owned test-run configuration")
    return candidates[0]


def published_app(out):
    dmg = out / "published.dmg"
    urllib.request.urlretrieve(DMG_URL, dmg)
    if hashlib.sha256(dmg.read_bytes()).hexdigest() != DMG_SHA256:
        raise RuntimeError("Published DMG checksum mismatch")
    mounted = plistlib.loads(subprocess.check_output(
        ["hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg)]))
    volumes = [Path(row["mount-point"]) for row in mounted["system-entities"] if "mount-point" in row]
    if len(volumes) != 1:
        raise RuntimeError("Ambiguous published DMG mount")
    app = out / "PerformanceDaddy.app"
    try:
        shutil.copytree(volumes[0] / "PerformanceDaddy.app", app, symlinks=True)
    finally:
        run("hdiutil", "detach", str(volumes[0]))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if str(info["CFBundleVersion"]) != "25" or info["CFBundleShortVersionString"] != "0.2.20":
        raise RuntimeError("Unexpected published version/build")
    run("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
        "LaunchServices.framework/Support/lsregister", "-f", str(app))
    return app, info


def configure_run(original, app, info, home, out):
    document = plistlib.loads(original.read_bytes())
    version = document.get("__xctestrun_metadata__", {}).get("FormatVersion", 1)
    if version == 1:
        targets = [target for key, target in document.items()
                   if key != "__xctestrun_metadata__"]
    elif version == 2:
        targets = [target for config in document.get("TestConfigurations", [])
                   for target in config.get("TestTargets", [])]
    else:
        raise RuntimeError("Unsupported test-run format")
    if len(targets) != 1 or targets[0].get("BlueprintName") != "PublishedAppUITests":
        raise RuntimeError("Unexpected test-run targets; refusing to retarget them")
    target = targets[0]
    if target.get("IsUITestBundle") is not True:
        raise RuntimeError("Expected the built UI testing bundle")
    target["UITargetAppPath"] = str(app)
    target["UITargetAppBundleIdentifier"] = info["CFBundleIdentifier"]
    target["UITargetAppEnvironmentVariables"] = {"CFFIXED_USER_HOME": str(home)}
    target.setdefault("EnvironmentVariables", {}).update({
        "PD_EPHEMERAL_UI_RUNNER": "true", "PD_EXPECTED_APP_PATH": str(app),
        "PD_PRIVATE_HOME": str(home), "PD_UI_OUTPUT": str(out),
    })
    target["ParallelizationEnabled"] = False
    target["TestLanguage"] = "en"
    target["TestRegion"] = "US"
    target["SystemAttachmentLifetime"] = "keepAlways"
    target["UserAttachmentLifetime"] = "keepAlways"
    target.setdefault("DependentProductPaths", []).append(str(app))
    patched = original.with_name("PublishedApp.published.xctestrun")
    patched.write_bytes(plistlib.dumps(document))
    return patched


def stop_owned_app(cli, app, out):
    executable = str(app / "Contents/MacOS/PerformanceDaddy")
    rows = run("ps", "-axo", "pid=,comm=").splitlines()
    matches = [int(row.split(None, 1)[0]) for row in rows
               if len(row.split(None, 1)) == 2 and row.split(None, 1)[1] == executable]
    if len(matches) > 1:
        raise RuntimeError("Ambiguous owned app cleanup; no process was stopped")
    if matches and run("ps", "-p", str(matches[0]), "-o", "comm=").strip() == executable:
        mcp(cli, out, "stop", "stop", {"processId": matches[0]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--tool-cli", type=Path)
    args = parser.parse_args()
    if os.uname().sysname != "Darwin":
        raise RuntimeError("Requires macOS")
    if not args.build_only and os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("GUI execution is restricted to an ephemeral GitHub Mac")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"scope": "Published 0.2.20/build25 minimum-window navigation and controls",
              "source": run("git", "-C", str(ROOT), "rev-parse", "HEAD").strip(),
              "os": run("sw_vers"), "arch": run("uname", "-m").strip(),
              "buildOnly": args.build_only, "result": "incomplete",
              "dirty": bool(run("git", "-C", str(ROOT), "status", "--porcelain").strip()),
              "inputs": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in [
                  "Tests/PublishedAppUITests/project.yml",
                  "Tests/PublishedAppUITests/PublishedAppUITests.swift",
                  "scripts/qualify-published-ui.py"]},
              "limitations": ["XCUITest reachability is not full VoiceOver traversal",
                              "No alert/load, energy, sleep/wake, hook or account-sync claim"]}
    app = None
    cli = args.tool_cli
    try:
        if cli is None:
            tools = out / "tools"
            run("npm", "install", "--prefix", str(tools), "--no-audit", "--no-fund",
                "xcodebuildmcp@2.7.0")
            cli = tools / "node_modules/xcodebuildmcp/build/cli.js"
        report["xcodeBuildMCP"] = run("node", str(cli), "--version").strip()
        if report["xcodeBuildMCP"] != "2.7.0":
            raise RuntimeError("Requires qualified XcodeBuildMCP 2.7.0")
        report["xcodegen"] = run("xcodegen", "--version").strip()
        configuration = build_runner(cli, out)
        if args.build_only:
            report["result"] = "runner-built-not-executed"
            return
        app, info = published_app(out)
        executable = app / "Contents/MacOS/PerformanceDaddy"
        report["published"] = {"dmgSha256": DMG_SHA256, "bundleId": info["CFBundleIdentifier"],
                               "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                               "executableSha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
        home = out / "private-home"
        home.mkdir()
        configuration = configure_run(configuration, app, info, home, out)
        mcp(cli, out, "test", "test", {
            "xctestrunPath": str(configuration),
            "extraArgs": ["-resultBundlePath", str(out / "PublishedUI.xcresult"),
                          "-parallel-testing-enabled", "NO"],
        })
        observations = json.loads((out / "ui-observations.json").read_text())
        qualified = [row["page"] for row in observations if row["stage"] == "page-qualified"]
        if qualified != PAGES or observations[-1].get("stage") != "completed":
            raise RuntimeError("Test returned without completing all eight required pages")
        if hashlib.sha256(executable.read_bytes()).hexdigest() != report["published"]["executableSha256"]:
            raise RuntimeError("Published executable changed during qualification")
        run("codesign", "--verify", "--deep", "--strict", str(app))
        report["pages"] = qualified
        report["result"] = "qualified"
    except Exception as error:
        report["result"] = "unqualified"
        report["error"] = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            report["commandStdout"] = error.stdout
            report["commandStderr"] = error.stderr
        raise
    finally:
        try:
            if app is not None:
                stop_owned_app(cli, app, out)
                report["ownedAppStopped"] = True
        finally:
            (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
