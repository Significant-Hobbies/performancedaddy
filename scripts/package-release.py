#!/usr/bin/env python3
"""Assemble and sign an isolated PerformanceDaddy candidate."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sparkle_support
import package_resources

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(value) for value in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    args = parser.parse_args()

    products = args.products.resolve()
    binary = products / "PerformanceDaddy"
    resources = products / "PerformanceDaddy_PerformanceDaddy.bundle"
    if products.name != "Release" or not binary.is_file() or not resources.is_dir():
        raise SystemExit("Expected existing Release binary and resource bundle")
    package_resources.resource_bundles(products)
    if args.build < 1 or not all(part.isdigit() for part in args.version.split(".")):
        raise SystemExit("Version must be numeric and build must be positive")
    sources = list((ROOT / "Sources").rglob("*.swift")) + [ROOT / "Package.swift"]
    if any(path.stat().st_mtime > binary.stat().st_mtime for path in sources):
        raise SystemExit("Source changed after the build; rebuild before packaging")

    expected = {"PageDoodles.png", "PerformanceDaddy.png", "StorageDaddy.png"}
    built_assets = resources / "Contents/Resources"
    if {path.name for path in built_assets.iterdir()} != expected:
        raise SystemExit("Unexpected or missing resource assets; use a fresh build")
    for name in expected:
        if (built_assets / name).read_bytes() != (ROOT / "Sources/PerformanceDaddy/Resources" / name).read_bytes():
            raise SystemExit("Built artwork is stale")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    stage = output / "image-contents"
    app = stage / "PerformanceDaddy.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    shutil.copy2(binary, contents / "MacOS/PerformanceDaddy")
    package_resources.copy_resources(products, contents / "Resources")
    shutil.copy2(ROOT / "Support/PerformanceDaddy.icns", contents / "Resources/PerformanceDaddy.icns")

    info = plistlib.loads((ROOT / "Support/Info.plist").read_bytes())
    info.update(CFBundleIdentifier="com.significanthobbies.performancedaddy",
                CFBundleShortVersionString=args.version, CFBundleVersion=str(args.build),
                **sparkle_support.configuration())
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))

    sparkle_support.embed(app)
    sparkle_support.sign(app, args.identity)
    run("codesign", "--force", "--sign", args.identity, "--timestamp", "--options", "runtime", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    (stage / "Applications").symlink_to("/Applications")
    dmg = output / f"PerformanceDaddy-{args.version}-{args.build}-universal.dmg"
    run("hdiutil", "create", "-volname", "PerformanceDaddy", "-srcfolder", stage, "-format", "UDZO", dmg)
    run("codesign", "--sign", args.identity, "--timestamp", dmg)
    run("hdiutil", "verify", dmg)
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {dmg.name}\n")
    print(f"Signed candidate only; notarization and runtime qualification remain: {dmg}")


if __name__ == "__main__":
    main()
