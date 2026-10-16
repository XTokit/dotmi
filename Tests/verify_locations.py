"""Verify adding a covered folder preserves the index and search selection."""
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

binary = os.environ['XUNJI_TEST_BINARY']
with tempfile.TemporaryDirectory(prefix='xunji-locations-') as temp:
    base = Path(temp).resolve()
    root, data = base / 'files', base / 'state'
    (root / '子目录').mkdir(parents=True)
    (root / '子目录/文稿.txt').write_text('personal document')
    (root / '子目录/.文稿.txt').write_text('hidden document')
    report = base / 'report.json'
    env = dict(os.environ, XUNJI_TEST_ROOT=str(root), XUNJI_DATA_DIR=str(data), XUNJI_RUN_REPORT=str(report))
    for mode in ['--verify-index-run', '--verify-locations', '--verify-search-feedback']:
        if mode == '--verify-search-feedback':
            # The fixture lives under /private/tmp, which production intentionally hides.
            # Give synthetic rows personal-file visibility without changing production rules.
            with sqlite3.connect(data / 'files.sqlite') as db:
                db.execute("UPDATE files SET noise = CASE WHEN name LIKE '.%' THEN 1 ELSE 0 END")
        run = subprocess.run([binary, mode], env=env, capture_output=True, text=True, timeout=50)
        assert run.returncode == 0, (run.returncode, run.stdout, run.stderr)
        print(run.stdout.strip(), flush=True)
    catalog = json.loads((data / 'index-state.json').read_text())
    assert str(root / '子目录') not in catalog['roots']
    with sqlite3.connect(data / 'files.sqlite') as db:
        assert db.execute('SELECT count(*) FROM files').fetchone()[0] == json.loads(report.read_text())['count']
    print('PASS: favorite operations do not create index roots, rescan or duplicate file records')
