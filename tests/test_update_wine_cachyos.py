import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "desktop" / "scripts" / "update-wine-cachyos.py"
SPEC = importlib.util.spec_from_file_location("update_wine_cachyos", SCRIPT)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class TagSelectionTests(unittest.TestCase):
    def test_selects_latest_regular_release(self):
        refs = "\n".join(
            [
                "aaa\trefs/tags/cachyos-11.0-20261014-base",
                "bbb\trefs/tags/cachyos-11.0-20261015-proton",
                "ccc\trefs/tags/cachyos-11.0-20261016-proton-dev",
                "ddd\trefs/tags/cachyos-10.0-20261201-wine",
                "eee\trefs/tags/experimental-wine-bleeding-edge-11.0-20261201",
            ]
        )
        self.assertEqual(updater.latest_tag(refs), "cachyos-11.0-20261015-proton")

    def test_prefers_regular_proton_when_release_dates_match(self):
        refs = "\n".join(
            [
                "aaa\trefs/tags/cachyos-11.0-20261015-proton-slr",
                "bbb\trefs/tags/cachyos-11.0-20261015-proton-native",
                "ccc\trefs/tags/cachyos-11.0-20261015-proton",
            ]
        )
        self.assertEqual(updater.latest_tag(refs), "cachyos-11.0-20261015-proton")

    def test_accepts_newer_standalone_wine_tag(self):
        refs = "\n".join(
            [
                "aaa\trefs/tags/cachyos-11.0-20261015-proton",
                "bbb\trefs/tags/cachyos-12.0-20270101-wine",
            ]
        )
        self.assertEqual(updater.latest_tag(refs), "cachyos-12.0-20270101-wine")

    def test_fails_when_no_regular_tags_exist(self):
        with self.assertRaisesRegex(ValueError, "No regular"):
            updater.latest_tag("aaa\trefs/tags/cachyos-11.0-20261015-proton-dev")


class FlakeUpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.flake = self.root / "flake.nix"
        self.original = (
            '{ inputs.wine-cachyos = {\n'
            '  url = "github:CachyOS/wine-cachyos/cachyos-11.0-20261015-proton";\n'
            "  flake = false;\n"
            "}; }\n"
        )
        self.flake.write_text(self.original, encoding="utf-8")
        self.latest = "cachyos-11.0-20261101-proton"

    def test_updates_tag_and_lock(self):
        with mock.patch.object(updater.subprocess, "run") as run:
            updater.update_flake(self.root, self.latest)
        self.assertIn(self.latest, self.flake.read_text(encoding="utf-8"))
        run.assert_called_once_with(
            ["nix", "flake", "update", "wine-cachyos"], cwd=self.root, check=True
        )

    def test_check_does_not_change_files(self):
        with mock.patch.object(updater.subprocess, "run") as run:
            updater.update_flake(self.root, self.latest, check_only=True)
        self.assertEqual(self.flake.read_text(encoding="utf-8"), self.original)
        run.assert_not_called()

    def test_already_current_does_not_update_lock(self):
        with mock.patch.object(updater.subprocess, "run") as run:
            updater.update_flake(self.root, "cachyos-11.0-20261015-proton")
        self.assertEqual(self.flake.read_text(encoding="utf-8"), self.original)
        run.assert_not_called()

    def test_restores_flake_when_lock_update_fails(self):
        failure = subprocess.CalledProcessError(1, ["nix", "flake", "update"])
        with mock.patch.object(updater.subprocess, "run", side_effect=failure):
            with self.assertRaisesRegex(RuntimeError, "flake.nix was restored"):
                updater.update_flake(self.root, self.latest)
        self.assertEqual(self.flake.read_text(encoding="utf-8"), self.original)

    def test_preserves_concurrent_changes_on_lock_failure(self):
        def fail_after_edit(*args, **kwargs):
            with self.flake.open("a", encoding="utf-8") as file:
                file.write("# concurrent change\n")
            raise subprocess.CalledProcessError(1, ["nix", "flake", "update"])

        with mock.patch.object(updater.subprocess, "run", side_effect=fail_after_edit):
            with self.assertRaisesRegex(RuntimeError, "changed concurrently"):
                updater.update_flake(self.root, self.latest)
        self.assertIn("# concurrent change", self.flake.read_text(encoding="utf-8"))
        self.assertIn(self.latest, self.flake.read_text(encoding="utf-8"))

    def test_refuses_to_overwrite_a_concurrent_change(self):
        with mock.patch.object(Path, "read_text", side_effect=[self.original, "changed"]):
            with self.assertRaisesRegex(RuntimeError, "changed while checking tags"):
                updater.update_flake(self.root, self.latest)
        self.assertEqual(self.flake.read_text(encoding="utf-8"), self.original)

    def test_refuses_to_downgrade(self):
        with mock.patch.object(updater.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "Refusing"):
                updater.update_flake(self.root, "cachyos-10.0-20261201-wine")
        self.assertEqual(self.flake.read_text(encoding="utf-8"), self.original)
        run.assert_not_called()

    def test_requires_exactly_one_input(self):
        self.flake.write_text(self.original + self.original, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            updater.update_flake(self.root, self.latest)


if __name__ == "__main__":
    unittest.main()
