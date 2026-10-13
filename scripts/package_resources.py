"""Copy required SwiftPM resources into an assembled app, without signing."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import uuid

BUNDLE_NAMES = ("PerformanceDaddy_PerformanceDaddy.bundle", "SaaSMakerUI_SaaSMakerUI.bundle")


def resource_bundles(products: Path) -> tuple[Path, ...]:
    bundles = tuple(products / name for name in BUNDLE_NAMES)
    for bundle in bundles:
        if not bundle.is_dir():
            raise SystemExit(f"Missing required SwiftPM resource bundle: {bundle}. Rebuild before packaging.")
    return bundles


def copy_resources(products: Path, destination: Path) -> None:
    bundles = resource_bundles(products)
    destination.mkdir(parents=True, exist_ok=True)
    for bundle in bundles:
        shutil.copytree(bundle, destination / bundle.name, dirs_exist_ok=True)


def check_startup(products: Path, app: Path) -> None:
    """Require packaged fonts and the actual window without build-path fallbacks."""
    bundles = resource_bundles(products)
    held = []
    try:
        for bundle in bundles:
            relocated = bundle.with_name(f".{bundle.name}.startup-check-{uuid.uuid4().hex}")
            bundle.rename(relocated)
            held.append((bundle, relocated))
        executable = app.resolve() / "Contents/MacOS/PerformanceDaddy"
        for flag, marker in (("--check-ui-resources", "PerformanceDaddy UI resources loaded"),
                             ("--check-app-startup", "PerformanceDaddy app startup verified")):
            result = subprocess.run([str(executable), flag], check=True, timeout=30,
                                    capture_output=True, text=True)
            if marker not in result.stdout.splitlines():
                raise RuntimeError(f"Packaged app did not complete {flag}")
            print(marker)
    finally:
        for bundle, relocated in reversed(held):
            relocated.rename(bundle)


def bundle_hashes(bundle: Path) -> dict[str, str]:
    hashes = {}
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"Resource bundle symlink is not allowed: {path}")
        if path.is_file():
            hashes[path.relative_to(bundle).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not hashes:
        raise SystemExit(f"Empty SwiftPM resource bundle: {bundle}")
    return hashes


def stage_universal_library(root: Path, destination: Path) -> None:
    """Extend the pinned universal builder's app-only resource copy locally."""
    bundles = []
    for architecture in ("arm64", "x86_64"):
        scratch = root / ".build" / f"daddy-release-{architecture}"
        matches = [path for path in scratch.rglob(BUNDLE_NAMES[1])
                   if path.is_dir() and path.parent.name.lower() == "release"]
        if len(matches) != 1:
            raise SystemExit(f"Expected one {architecture} Release {BUNDLE_NAMES[1]} in {scratch}")
        bundles.append(matches[0])
    hashes = bundle_hashes(bundles[0])
    if hashes != bundle_hashes(bundles[1]):
        raise SystemExit("SaaSMakerUI Release resource bundles differ between architectures")
    target = destination / BUNDLE_NAMES[1]
    shutil.copytree(bundles[0], target)
    if bundle_hashes(target) != hashes:
        raise SystemExit("Copied SaaSMakerUI Release resources do not match the verified source")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--products", type=Path)
    source.add_argument("--universal-root", type=Path)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    if args.universal_root:
        stage_universal_library(args.universal_root, args.destination)
    else:
        copy_resources(args.products, args.destination)
