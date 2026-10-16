"""Measure native app CPU/RSS on synthetic files; never uses personal index data."""
import json
import os
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path

binary = os.environ['XUNJI_TEST_BINARY']
output = Path(os.environ['XUNJI_PERFORMANCE_REPORT'])

def cpu_seconds(value):
    minutes, seconds = value.strip().split(':')
    return float(minutes) * 60 + float(seconds)

with tempfile.TemporaryDirectory(prefix='dotmi-performance-') as directory:
    base = Path(directory).resolve(); root = base / 'files'; root.mkdir()
    data = base / 'state'
    for n in range(30000):
        folder = root / f'项目{n // 1000:02d}'; folder.mkdir(exist_ok=True)
        (folder / f'文稿方案{n:05d}.txt').touch()
    results = []
    for phase in ['initial_scan', 'idle_restart', 'burst_changes']:
        report = base / f'{phase}.json'
        env = dict(os.environ, XUNJI_TEST_ROOT=str(root), XUNJI_DATA_DIR=str(data), XUNJI_RUN_REPORT=str(report), XUNJI_SETTLE_SECONDS='10')
        started = time.monotonic(); samples = []; changed_at = None
        with (base / 'stdout').open('w') as log:
            proc = subprocess.Popen([binary, '--verify-index-run'], env=env, stdout=log, stderr=log)
            try:
                while proc.poll() is None:
                    elapsed = time.monotonic() - started
                    if elapsed > 50: raise TimeoutError(phase)
                    sample = subprocess.run(['/bin/ps', '-p', str(proc.pid), '-o', 'time=,rss='], capture_output=True, text=True).stdout.split()
                    if len(sample) == 2:
                        samples.append((elapsed, cpu_seconds(sample[0]), int(sample[1])))
                    if phase == 'burst_changes' and elapsed > 3 and changed_at is None:
                        changed_at = time.monotonic()
                        for n in range(1000): (root / '项目00' / f'新增{n:04d}.pdf').touch()
                        for n in range(500): (root / '项目00' / f'文稿方案{n:05d}.txt').rename(root / '项目00' / f'改名{n:05d}.txt')
                        for n in range(500, 1000): (root / '项目00' / f'文稿方案{n:05d}.txt').unlink()
                    time.sleep(0.5)
                assert proc.returncode == 0, (phase, (base / 'stdout').read_text())
            finally:
                if proc.poll() is None: proc.kill(); proc.wait()
        value = json.loads(report.read_text())
        assert value['accelerated'] and value['coverage'][0]['state'] == 'ready'
        expected = 30530 if phase == 'burst_changes' else 30030
        assert value['count'] == expected, (phase, value['count'])
        if results and phase == 'idle_restart':
            assert value['coverage'][0]['lastScan'] == results[0]['last_scan'], 'Unexpected full baseline scan'
        steady = [s for s in samples if s[0] >= 4]
        steady_cpu = (steady[-1][1] - steady[0][1]) / (steady[-1][0] - steady[0][0]) * 100 if len(steady) > 1 else None
        result = dict(phase=phase, wall_seconds=round(time.monotonic()-started,2), sampled_cpu_seconds=samples[-1][1], peak_rss_mib=round(max(s[2] for s in samples)/1024,1), cpu_percent_after_4s=round(steady_cpu,2) if steady_cpu is not None else None, count=value['count'], last_scan=value['coverage'][0]['lastScan'], baseline_rescanned=bool(results and value['coverage'][0]['lastScan'] != results[0]['last_scan']))
        if phase == 'burst_changes':
            with sqlite3.connect(data / 'files.sqlite') as db:
                assert db.execute("SELECT count(*) FROM files WHERE name LIKE '新增%'").fetchone()[0] == 1000
                assert db.execute("SELECT count(*) FROM files WHERE name LIKE '改名%'").fetchone()[0] == 500
        results.append(result)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({'synthetic_files': 30000, 'sample_interval_seconds': 0.5, 'results': results}, indent=2))
        print(json.dumps(result), flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({'synthetic_files': 30000, 'sample_interval_seconds': 0.5, 'results': results}, indent=2))
print('PASS: initial scan, unchanged restart, live burst of 1000 creates / 500 renames / 500 deletes, no full rescan on unchanged restart; burst event recovery recorded separately')
