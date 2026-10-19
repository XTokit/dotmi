"""Check rapid feedback replacement and clipboard operations without personal data."""
import os
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='dotmi-interaction-') as directory:
    env = dict(os.environ, XUNJI_DATA_DIR=directory)
    run = subprocess.run([os.environ['XUNJI_TEST_BINARY'], '--verify-interaction'],
                         env=env, capture_output=True, text=True, timeout=20)
    assert run.returncode == 0, (run.returncode, run.stdout, run.stderr)
    assert 'PASS: isolated clipboard' in run.stdout
    print(run.stdout.strip())
