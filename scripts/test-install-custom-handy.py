import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install-custom-handy.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.check_output(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', *args], text=True).strip()

    def app(self, path, binary, identifier=installer.IDENTIFIER):
        (path / 'Contents/MacOS').mkdir(parents=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier}))
        (path / 'Contents/MacOS/handy').write_bytes(binary)
        return path

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / 'root'
        self.root.mkdir()
        self.git(self.root, 'init', '-q')
        (self.root / '.gitignore').write_text('.custom-updates.local/\n')
        (self.root / 'custom').write_text('preserve me')
        self.git(self.root, 'add', '.')
        self.git(self.root, 'commit', '-qm', 'base')
        self.original = installer.revision(self.root)
        self.source = base / 'source'
        subprocess.run(['git', 'clone', '-q', str(self.root), str(self.source)], check=True)
        (self.source / 'updated').write_text('new release')
        self.git(self.source, 'add', '.')
        self.git(self.source, 'commit', '-qm', 'update')
        self.main = self.app(base / 'Applications/Handy.app', b'old')
        self.built = self.app(base / 'build/Handy.app', b'new')
        self.marker = self.root / '.custom-updates.local/installed.json'
        self.calls = []
        real_run = installer.run

        def fake_run(*args, **kwargs):
            self.calls.append(args)
            if args[0] == 'git':
                return real_run(*args, **kwargs)
            if args[0] == 'codesign' and getattr(self, 'bad_signature', False):
                raise RuntimeError('bad signature')
        self.addCleanup(patch.stopall)
        patch.object(installer, 'run', side_effect=fake_run).start()
        self.stop = patch.object(installer, 'stop').start()
        self.running = patch.object(installer, 'running', return_value=[123]).start()
        patch.object(installer.time, 'sleep').start()

    def install(self):
        installer.install(self.root, self.source, self.built, 'v1.0.1', self.original, self.main)

    def test_install_updates_main_preserves_custom_history_and_skips_identical_build(self):
        self.install()
        self.assertEqual((self.main / 'Contents/MacOS/handy').read_bytes(), b'new')
        self.assertEqual((self.root / 'custom').read_text(), 'preserve me')
        self.assertEqual(installer.revision(self.root), installer.revision(self.source))
        self.assertTrue(installer.is_current(self.root, 'v1.0.1', self.main))
        self.assertFalse(installer.is_current(self.root, 'v1.0.2', self.main))
        (self.main / 'Contents/MacOS/handy').write_bytes(b'changed')
        self.assertFalse(installer.is_current(self.root, 'v1.0.1', self.main))
        self.assertTrue(list((self.root / '.custom-updates.local/rollback').glob('*.app')))

    def test_bad_signature_never_quits_or_replaces_main(self):
        self.bad_signature = True
        with self.assertRaisesRegex(RuntimeError, 'signature'):
            self.install()
        self.stop.assert_not_called()
        self.assertEqual((self.main / 'Contents/MacOS/handy').read_bytes(), b'old')

    def test_dirty_source_stops_installation(self):
        (self.root / 'custom').write_text('unsaved changes')
        with self.assertRaisesRegex(RuntimeError, 'uncommitted'):
            self.install()
        self.stop.assert_not_called()

    def test_source_revision_changed_stops_installation(self):
        self.original = 'stale revision'
        with self.assertRaisesRegex(RuntimeError, 'changed'):
            self.install()
        self.stop.assert_not_called()

    def test_preview_identifier_cannot_replace_main(self):
        with (self.built / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': 'com.maticberglez.handy.preview'}, stream)
        with self.assertRaisesRegex(RuntimeError, 'identifier'):
            self.install()
        self.stop.assert_not_called()

    def test_failed_swap_restores_original(self):
        real_rename = installer.os.rename
        def fail_staging(src, dst):
            if Path(src).name.startswith('.Handy-installing'):
                raise OSError('replacement failed')
            return real_rename(src, dst)
        with patch.object(installer.os, 'rename', side_effect=fail_staging):
            with self.assertRaisesRegex(OSError, 'replacement failed'):
                self.install()
        self.assertEqual((self.main / 'Contents/MacOS/handy').read_bytes(), b'old')
        self.assertFalse(self.marker.exists())

    def test_launch_failure_restores_original_app_and_marker(self):
        self.marker.parent.mkdir(parents=True)
        old = json.dumps({'previous': True})
        self.marker.write_text(old)
        self.running.return_value = []
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            self.install()
        self.assertEqual((self.main / 'Contents/MacOS/handy').read_bytes(), b'old')
        self.assertEqual(self.marker.read_text(), old)
        self.assertFalse(list(self.main.parent.glob('.Handy-installing*')))


if __name__ == '__main__':
    unittest.main()
