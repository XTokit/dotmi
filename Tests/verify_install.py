"""Exercise name migration, repeat updates and rollback using a signed fixture bundle."""
import importlib.util
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
source = Path(os.environ['XUNJI_TEST_APP'])
real_run = subprocess.run
with tempfile.TemporaryDirectory(prefix='dotmi-install-check-') as directory:
    base = Path(directory)
    apps = base / 'Applications'; apps.mkdir()
    data = base / 'user-data'; data.write_bytes(b'index-and-preferences-preserved')
    old = apps / installer.LEGACY_NAME
    new = apps / installer.APP_NAME
    shutil.copytree(source, old)
    def checked_run(args, **kwargs):
        if args[0] == installer.LSREGISTER:
            return subprocess.CompletedProcess(args, 0)
        return real_run(args, **kwargs)
    with patch.object(installer, 'stop_application'), patch.object(installer.subprocess, 'run', side_effect=checked_run):
        installer.install(source, apps)
        assert new.exists() and not old.exists()
        installer.install(source, apps)
        assert [p.name for p in apps.iterdir()] == [installer.APP_NAME]
        signature = (new / 'Contents/MacOS/Xunji').read_bytes()
        def fail_registration(args, **kwargs):
            if args[0] == installer.LSREGISTER:
                raise subprocess.CalledProcessError(1, args)
            return real_run(args, **kwargs)
        with patch.object(installer.subprocess, 'run', side_effect=fail_registration):
            try: installer.install(source, apps)
            except subprocess.CalledProcessError: pass
            else: raise AssertionError('Expected registration failure')
        assert (new / 'Contents/MacOS/Xunji').read_bytes() == signature
        new.rename(old)
        with patch.object(installer.subprocess, 'run', side_effect=fail_registration):
            try: installer.install(source, apps)
            except subprocess.CalledProcessError: pass
            else: raise AssertionError('Expected migration failure')
        assert old.exists() and not new.exists()
        with (old / 'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
        info['CFBundleIdentifier'] = 'unrelated.app'
        with (old / 'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
        try: installer.install(source, apps)
        except RuntimeError: pass
        else: raise AssertionError('Unrelated application must not be replaced')
        assert old.exists() and data.read_bytes() == b'index-and-preferences-preserved'
print('PASS: legacy name migration, single installation, repeat update, failed registration rollback, old-name rollback, unrelated app refusal; isolated data untouched')
