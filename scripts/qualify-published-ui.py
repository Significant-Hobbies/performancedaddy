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
import package_resources
import sparkle_support

ROOT = Path(__file__).resolve().parent.parent
DMG_SHA256 = "cc7b6e68600f84fefcdff54d39d6eaf5719ecfe4037b8c98386f882aed51f551"
DMG_URL = ("https://github.com/Significant-Hobbies/performancedaddy/releases/download/"
           "v0.2.20-25/performancedaddy-0.2.20-build25-universal.dmg")
PAGES = ["Processes", "Ports", "Agent sessions", "Memory", "Fans & heat",
         "App access", "Configuration", "Diagnose"]


def run(*command, timeout=180, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True,
                          timeout=timeout, **kwargs).stdout


def mcp(cli, out, label, operation, arguments, *, workflow="macos", allow_test_failure=False):
    command = ["node", str(cli), workflow, operation, "--json", json.dumps(arguments),
               "--output", "json"]
    result = subprocess.run(command, text=True, capture_output=True, timeout=1500 if operation == "test" else 900, cwd=ROOT)
    (out / f"{label}.stdout.json").write_text(result.stdout)
    (out / f"{label}.stderr.txt").write_text(result.stderr)
    payload = json.loads(result.stdout)
    failed_test = (operation == "test" and allow_test_failure and
                   payload.get("data", {}).get("summary", {}).get("counts", {}).get("failed") == 1)
    if (result.returncode or payload.get("didError") is not False) and not failed_test:
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
    return app, info


def candidate_app(cli, out):
    mcp(cli, out, "candidate-build", "build", {
        "packagePath": str(ROOT), "configuration": "release",
    }, workflow="swift-package")
    products = (ROOT / ".build/release").resolve(strict=True)
    app = out / "PerformanceDaddy.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    resources = contents / "Resources"
    package_resources.copy_resources(products, resources)
    shutil.copy2(products / "PerformanceDaddy", contents / "MacOS/PerformanceDaddy")
    shutil.copy2(ROOT / "Support/PerformanceDaddy.icns", resources)
    info = plistlib.loads((ROOT / "Support/Info.plist").read_bytes())
    info.update(CFBundleIdentifier="com.significanthobbies.performancedaddy.qualification",
                CFBundleShortVersionString="0.0.0", CFBundleVersion="1")
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    sparkle_support.embed(app)
    sparkle_support.sign(app, "-", timestamp=False)
    run("codesign", "--force", "--deep", "--sign", "-", str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    return app, info


def configure_run(original, app, info, home, out, widths, expect_overflow=False):
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
        "PD_UI_WIDTHS": ",".join(map(str, widths)),
        "PD_EXPECT_NAVIGATION_OVERFLOW": str(expect_overflow).lower(),
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
    parser.add_argument("--candidate", action="store_true",
                        help="Build and qualify an ad-hoc signed source candidate; never publish it")
    parser.add_argument("--expect-navigation-overflow", action="store_true",
                        help="Require the known published-build navigation failure as a negative control")
    parser.add_argument("--window-width", type=int, choices=[980, 1180, 1440],
                        help="Qualify one candidate width per isolated CI job")
    args = parser.parse_args()
    if args.window_width is not None and not args.candidate:
        parser.error("A specific window width requires a source candidate")
    if args.expect_navigation_overflow and (args.candidate or args.build_only):
        parser.error("The negative control requires the unchanged published app")
    if os.uname().sysname != "Darwin":
        raise RuntimeError("Requires macOS")
    if not args.build_only and os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("GUI execution is restricted to an ephemeral GitHub Mac")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    widths = ([args.window_width] if args.window_width is not None
              else [980, 1180, 1440] if args.candidate else [980])
    report = {"scope": "Window bounds, all sidebar navigation and selected essential controls",
              "appKind": "source-candidate" if args.candidate else "published-0.2.20-build25",
              "expectedNavigationOverflow": args.expect_navigation_overflow,
              "windowWidths": widths,
              "source": run("git", "-C", str(ROOT), "rev-parse", "HEAD").strip(),
              "os": run("sw_vers"), "arch": run("uname", "-m").strip(),
              "buildOnly": args.build_only, "result": "incomplete",
              "dirty": bool(run("git", "-C", str(ROOT), "status", "--porcelain").strip()),
              "inputs": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in [
                  "Tests/PublishedAppUITests/project.yml",
                  "Tests/PublishedAppUITests/PublishedAppUITests.swift",
                  "scripts/ci-display-qualification.c",
                  "scripts/qualify-published-ui.py", "Sources/PerformanceDaddy/DashboardView.swift"]},
              "limitations": ["XCUITest reachability is not full VoiceOver traversal",
                              "Layout uses the app Pause control; continuous-live rendering remains unqualified",
                              "No alert/load, energy, sleep/wake, hook or account-sync claim"]}
    app = None
    display = None
    original_mode = None
    cli = args.tool_cli
    try:
        if not args.build_only:
            display = out / "ci-display"
            run("cc", str(ROOT / "scripts/ci-display-qualification.c"),
                "-framework", "CoreGraphics", "-framework", "CoreFoundation", "-o", str(display))
            configured = subprocess.run([str(display)], text=True, capture_output=True, timeout=30)
            (out / "display.json").write_text(configured.stdout)
            report["display"] = json.loads(configured.stdout)
            if report["display"]["changed"]:
                original_mode = report["display"]["before"]["id"]
            if configured.returncode:
                raise RuntimeError("Hosted display cannot provide the required graphical test area")
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
        app, info = candidate_app(cli, out) if args.candidate else published_app(out)
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
            "LaunchServices.framework/Support/lsregister", "-f", str(app))
        executable = app / "Contents/MacOS/PerformanceDaddy"
        report["app"] = {"dmgSha256": None if args.candidate else DMG_SHA256,
                               "bundleId": info["CFBundleIdentifier"],
                               "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                               "executableSha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
        home = out / "private-home"
        home.mkdir()
        configuration = configure_run(configuration, app, info, home, out, widths, args.expect_navigation_overflow)
        test_result = mcp(cli, out, "test", "test", {
            "xctestrunPath": str(configuration),
            "extraArgs": ["-resultBundlePath", str(out / "PublishedUI.xcresult"),
                          "-parallel-testing-enabled", "NO"],
        }, allow_test_failure=args.expect_navigation_overflow)
        observations = json.loads((out / "ui-observations.json").read_text())
        qualified = [row["page"] for row in observations if row["stage"] == "page-qualified"]
        if not any(row["stage"] == "sampling-paused" for row in observations):
            raise RuntimeError("Layout qualification requires paused live sampling")
        report["samplingPaused"] = True
        counts = test_result.get("data", {}).get("summary", {}).get("counts", {})
        if args.expect_navigation_overflow:
            failures = test_result.get("data", {}).get("diagnostics", {}).get("testFailures", [])
            last = observations[-1]
            if (counts != {"passed": 0, "failed": 1, "skipped": 0} or
                    not any("Navigation split group must fit inside the window" in str(f) for f in failures) or
                    last.get("stage") != "layout-observed" or last.get("page") != "Diagnose" or
                    last.get("navigationSplitGroup", {}).get("height", 0) <= last["window"]["height"] or
                    qualified != []):
                raise RuntimeError("The published app did not fail at the expected navigation overflow")
        elif (counts != {"passed": 1, "failed": 0, "skipped": 0} or
              qualified != PAGES * len(widths) or observations[-1].get("stage") != "completed"):
            raise RuntimeError("Test did not qualify every page at every required width")
        if hashlib.sha256(executable.read_bytes()).hexdigest() != report["app"]["executableSha256"]:
            raise RuntimeError("App executable changed during qualification")
        run("codesign", "--verify", "--deep", "--strict", str(app))
        report["pages"] = qualified
        report["result"] = ("known-published-overflow-reproduced" if args.expect_navigation_overflow
                            else "source-candidate-qualified" if args.candidate else "published-app-qualified")
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
            try:
                if original_mode is not None:
                    restored = run(str(display), "--restore", str(original_mode), timeout=30)
                    (out / "display-restored.json").write_text(restored)
                    report["displayRestored"] = True
            finally:
                (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
