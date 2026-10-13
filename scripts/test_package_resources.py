from pathlib import Path
import runpy
import sys
import tempfile
import unittest
import subprocess
from unittest.mock import patch

import package_resources


class PackageResourceTests(unittest.TestCase):
    def release_main(self, products, output):
        script = Path(__file__).with_name("package-release.py")
        main = runpy.run_path(str(script))["main"]
        arguments = [str(script), "--products", str(products), "--output", str(output),
                     "--identity", "unused", "--version", "1.0.0", "--build", "1"]
        with patch.object(sys, "argv", arguments):
            main()

    def test_release_entrypoint_rejects_missing_library_before_assembly(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            products = root / "Release"
            (products / package_resources.BUNDLE_NAMES[0]).mkdir(parents=True)
            (products / "PerformanceDaddy").write_bytes(b"fixture binary")
            output = root / "output"
            with self.assertRaisesRegex(SystemExit, "Missing required SwiftPM resource bundle.*SaaSMakerUI"):
                self.release_main(products, output)
            self.assertFalse(output.exists())

    def test_copies_app_artwork_and_library_fonts_next_to_each_other(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            products = root / "Release"
            for name, asset in zip(package_resources.BUNDLE_NAMES, ("PageDoodles.png", "Figtree.ttf")):
                resources = products / name / "Contents/Resources"
                resources.mkdir(parents=True)
                (resources / asset).write_bytes(asset.encode())
            destination = root / "PerformanceDaddy.app/Contents/Resources"
            package_resources.copy_resources(products, destination)
            for name, asset in zip(package_resources.BUNDLE_NAMES, ("PageDoodles.png", "Figtree.ttf")):
                self.assertEqual((destination / name / "Contents/Resources" / asset).read_bytes(), asset.encode())

    def test_missing_either_bundle_fails_before_modifying_destination(self):
        for missing in package_resources.BUNDLE_NAMES:
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                products = root / "Release"
                for name in package_resources.BUNDLE_NAMES:
                    if name != missing:
                        (products / name).mkdir(parents=True)
                destination = root / "PerformanceDaddy.app/Contents/Resources"
                with self.assertRaisesRegex(SystemExit, missing):
                    package_resources.copy_resources(products, destination)
                self.assertFalse(destination.exists())

    def test_file_instead_of_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            products = Path(folder)
            (products / package_resources.BUNDLE_NAMES[0]).mkdir()
            (products / package_resources.BUNDLE_NAMES[1]).write_text("not a bundle")
            with self.assertRaisesRegex(SystemExit, "SaaSMakerUI_SaaSMakerUI.bundle"):
                package_resources.resource_bundles(products)

    def test_startup_probes_require_real_window_and_restore_build_bundles(self):
        for error in (None, subprocess.CalledProcessError(5, ["fixture"]),
                      subprocess.TimeoutExpired(["fixture"], 30), RuntimeError("no marker")):
            with self.subTest(error=error), tempfile.TemporaryDirectory() as folder:
                products = Path(folder) / "Debug"
                for name in package_resources.BUNDLE_NAMES:
                    (products / name).mkdir(parents=True)
                commands = []

                def probe(command, **kwargs):
                    self.assertTrue(all(not (products / name).exists() for name in package_resources.BUNDLE_NAMES))
                    commands.append(command)
                    if command[1] == "--check-app-startup":
                        if isinstance(error, RuntimeError):
                            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
                        if error:
                            raise error
                        marker = "PerformanceDaddy app startup verified"
                    else:
                        marker = "PerformanceDaddy UI resources loaded"
                    return subprocess.CompletedProcess(command, 0, stdout=marker + "\n", stderr="")

                with patch("subprocess.run", side_effect=probe):
                    if error:
                        with self.assertRaises(type(error)):
                            package_resources.check_startup(products, Path(folder) / "PerformanceDaddy.app")
                    else:
                        package_resources.check_startup(products, Path(folder) / "PerformanceDaddy.app")
                self.assertEqual([c[1] for c in commands], ["--check-ui-resources", "--check-app-startup"])
                self.assertTrue(all((products / name).is_dir() for name in package_resources.BUNDLE_NAMES))

    def make_architecture_bundles(self, root):
        bundles = []
        for architecture in ("arm64", "x86_64"):
            bundle = root / ".build" / f"daddy-release-{architecture}" / "Products/Release" / package_resources.BUNDLE_NAMES[1]
            bundle.mkdir(parents=True)
            (bundle / "Figtree.ttf").write_bytes(b"bundled font")
            bundles.append(bundle)
        return bundles

    def test_universal_staging_preserves_verified_library_resources(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundles = self.make_architecture_bundles(root)
            output = root / "universal/Release"
            output.mkdir(parents=True)
            package_resources.stage_universal_library(root, output)
            self.assertEqual(package_resources.bundle_hashes(output / package_resources.BUNDLE_NAMES[1]),
                             package_resources.bundle_hashes(bundles[0]))

    def test_universal_mismatched_resources_fail_before_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundles = self.make_architecture_bundles(root)
            (bundles[1] / "Figtree.ttf").write_bytes(b"different font")
            output = root / "universal/Release"
            with self.assertRaisesRegex(SystemExit, "differ between architectures"):
                package_resources.stage_universal_library(root, output)
            self.assertFalse(output.exists())

    def test_universal_missing_architecture_bundle_is_clear(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(SystemExit, "arm64 Release SaaSMakerUI"):
                package_resources.stage_universal_library(root, root / "universal/Release")

    def test_resource_hashing_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle = self.make_architecture_bundles(root)[0]
            (bundle / "font-link").symlink_to(bundle / "Figtree.ttf")
            with self.assertRaisesRegex(SystemExit, "symlink is not allowed"):
                package_resources.bundle_hashes(bundle)


if __name__ == "__main__":
    unittest.main()
