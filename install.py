"""Install one stable application bundle without changing user data."""
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

APPLICATIONS = Path("/Applications")
APP_NAME = "点觅.app"
LEGACY_NAME = "寻迹.app"
BUNDLE_ID = "local.tokit.xunji"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def bundle_id(path):
    with (path / "Contents/Info.plist").open("rb") as handle:
        return plistlib.load(handle).get("CFBundleIdentifier")


def stop_application(path):
    executable = str(path / "Contents/MacOS/Xunji")
    listing = subprocess.check_output(["/bin/ps", "-axo", "pid=,command="], text=True)
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        command = fields[1]
        if command != executable and not command.startswith(executable + " "):
            continue
        pid = int(fields[0])
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        for _ in range(30):
            result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True)
            if result.returncode != 0 or result.stdout.strip().startswith("Z"):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("The running application did not exit; installation was not changed.")


def install(source, applications=APPLICATIONS):
    destination = applications / APP_NAME
    legacy = applications / LEGACY_NAME
    if source.is_symlink() or bundle_id(source) != BUNDLE_ID:
        raise RuntimeError("Unexpected source bundle identifier")
    installed = [path for path in (destination, legacy) if path.exists() or path.is_symlink()]
    for path in installed:
        if path.is_symlink() or bundle_id(path) != BUNDLE_ID:
            raise RuntimeError(f"Refusing to replace an unrelated application: {path}")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    # Both old and new names remain recoverable until the replacement is verified.
    with tempfile.TemporaryDirectory(prefix=".dotmi-update-", dir=applications) as directory:
        stage = Path(directory) / APP_NAME
        backups = []
        shutil.copytree(source, stage, symlinks=True)
        for path in installed:
            stop_application(path)
        try:
            for index, path in enumerate(installed):
                backup = Path(directory) / f"previous-{index}.app"
                path.rename(backup)
                backups.append((path, backup))
            stage.rename(destination)
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)], check=True)
            subprocess.run([LSREGISTER, "-f", str(destination)], check=True)
        except Exception:
            if not stage.exists() and destination.exists():
                shutil.rmtree(destination)
            for path, backup in reversed(backups):
                backup.rename(path)
            raise
    if legacy in installed:
        subprocess.run([LSREGISTER, "-u", str(legacy)], check=False, capture_output=True)
    print(f"Installed / updated: {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 install.py <source.app>")
    install(Path(sys.argv[1]).resolve())
