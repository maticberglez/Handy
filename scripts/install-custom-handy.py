#!/usr/bin/env python3
"""Install a verified custom build, preserving the previous app for rollback."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime

MAIN_APP = Path('/Applications/Handy.app')
IDENTIFIER = 'com.maticberglez.handy.custom'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def revision(root):
    return subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()


def binary_hash(app):
    return hashlib.sha256((app / 'Contents/MacOS/handy').read_bytes()).hexdigest()


def is_current(root, release, app=MAIN_APP):
    try:
        marker = json.loads((root / '.custom-updates.local/installed.json').read_text())
        return (marker['source_revision'] == revision(root)
                and marker['release'] == release
                and marker['binary_hash'] == binary_hash(app))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
        return False


def running(app):
    executable = str(app / 'Contents/MacOS/handy')
    processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
    return [int(parts[0]) for line in processes.splitlines()
            if len(parts := line.strip().split(None, 1)) == 2 and parts[1] == executable]


def stop(app):
    for pid in running(app):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(100):
        if not running(app):
            return
        time.sleep(.1)
    raise RuntimeError('Handy did not quit; installation was cancelled.')


def install(root, source, built, release, expected_revision, app=MAIN_APP):
    base = root / '.custom-updates.local'
    with (built / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream)['CFBundleIdentifier'] != IDENTIFIER:
            raise RuntimeError('Build identifier does not match everyday Handy.')
    if app.exists():
        with (app / 'Contents/Info.plist').open('rb') as stream:
            if plistlib.load(stream)['CFBundleIdentifier'] != IDENTIFIER:
                raise RuntimeError('Installed Handy has a different identifier; nothing was replaced.')
    run('codesign', '--verify', '--deep', str(built))
    if revision(root) != expected_revision:
        raise RuntimeError('Custom source changed during the build. Retry the update.')
    if subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip():
        raise RuntimeError('Custom source has uncommitted changes. Nothing was installed.')
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    staging = app.parent / f'.Handy-installing-{stamp}.app'
    backup = base / 'rollback' / f'Handy-{stamp}.app'
    backup.parent.mkdir(parents=True, exist_ok=True)
    marker = base / 'installed.json'
    old_marker = marker.read_bytes() if marker.exists() else None
    swapped = False
    stopped = False
    try:
        shutil.copytree(built, staging, symlinks=True)
        run('codesign', '--verify', '--deep', str(staging))
        # Retain the merged custom history so the next update starts here.
        run('git', '-C', str(root), 'fetch', str(source), 'HEAD')
        if revision(root) != expected_revision or subprocess.check_output(
                ['git', '-C', str(root), 'status', '--porcelain'], text=True).strip():
            raise RuntimeError('Custom source changed during installation. Nothing was replaced.')
        run('git', '-C', str(root), 'merge', '--ff-only', 'FETCH_HEAD')
        settings = Path.home() / 'Library/Application Support' / IDENTIFIER / 'settings_store.json'
        if settings.is_file():
            shutil.copy2(settings, backup.parent / f'settings-{stamp}.json')
        stop(app)
        stopped = True
        if app.exists():
            os.rename(app, backup)
        try:
            os.rename(staging, app)
        except BaseException:
            if backup.exists():
                os.rename(backup, app)
            raise
        swapped = True
        record = {'source_revision': revision(root), 'release': release, 'binary_hash': binary_hash(app)}
        pending = marker.with_suffix('.tmp')
        pending.write_text(json.dumps(record))
        os.replace(pending, marker)
        run('open', str(app))
        time.sleep(2)
        if not running(app):
            raise RuntimeError('Updated Handy exited on launch.')
        print(f'Installed {release} into {app}. Handy restarted successfully.', flush=True)
        print(f'Previous app saved at {backup}', flush=True)
    except BaseException:
        if swapped:
            stop(app)
            shutil.rmtree(app)
            if backup.exists():
                os.rename(backup, app)
                run('open', str(app))
            if old_marker is None:
                marker.unlink(missing_ok=True)
            else:
                marker.write_bytes(old_marker)
            print('Installation failed; the previous Handy app was restored.', flush=True)
        elif stopped and app.exists():
            run('open', str(app))
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)


if __name__ == '__main__':
    try:
        if sys.argv[1] == '--is-current':
            sys.exit(0 if is_current(Path(sys.argv[2]), sys.argv[3]) else 1)
        _, root, source, built, release, expected = sys.argv
        install(Path(root), Path(source), Path(built), release, expected)
    except Exception as error:
        print(f'Installation error: {error}', file=sys.stderr, flush=True)
        sys.exit(1)
