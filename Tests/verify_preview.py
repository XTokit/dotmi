"""Run the native preview lifecycle regression in an isolated data directory."""
import os
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='xunji-preview-') as directory:
    env = dict(os.environ, XUNJI_DATA_DIR=directory)
    run = subprocess.run([os.environ['XUNJI_TEST_BINARY'], '--verify-preview'], env=env,
                         capture_output=True, text=True, timeout=25)
    assert run.returncode == 0, (run.returncode, run.stdout, run.stderr)
    assert 'PASS: 30 preview transitions' in run.stdout
    print(run.stdout.strip())
