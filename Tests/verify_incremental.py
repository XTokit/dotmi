# -*- coding: utf-8 -*-
"""Exercise actual FSEvents replay across independent application launches."""
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

binary = Path(os.environ['XUNJI_TEST_BINARY'])
with tempfile.TemporaryDirectory(prefix='xunji-incremental-') as directory:
    base = Path(directory).resolve()
    root, data = base / 'files', base / 'state'
    (root / '子目录').mkdir(parents=True)
    (root / 'node_modules').mkdir()
    (root / '旧文件.txt').write_text('old', encoding='utf-8')
    (root / '子目录/初稿.md').write_text('draft', encoding='utf-8')
    (root / 'node_modules/ignored.txt').write_text('ignored', encoding='utf-8')
    env = dict(os.environ, XUNJI_TEST_ROOT=str(root), XUNJI_DATA_DIR=str(data))

    def run(number):
        report = base / f'report-{number}.json'
        result = subprocess.run([str(binary), '--verify-index-run'], env=dict(env, XUNJI_RUN_REPORT=str(report)), capture_output=True, text=True, timeout=50)
        if result.returncode != 0:
            raise AssertionError((result.returncode, result.stdout, result.stderr))
        value = json.loads(report.read_text())
        assert value['accelerated']
        print(f'Launch {number}: {result.stdout.strip()}', flush=True)
        return value

    first = run(1)
    assert first['coverage'][0]['state'] == 'ready'
    assert str(root / 'node_modules') in first['coverage'][0]['excluded']
    original_date = first['coverage'][0]['lastScan']
    (root / '旧文件.txt').rename(root / '改名文件.txt')
    (root / '子目录/初稿.md').unlink()
    (root / '子目录/新增文件.txt').write_text('new', encoding='utf-8')
    (root / '子目录').rename(root / '重命名目录')
    (root / '新目录').mkdir()
    (root / '新目录/移动后的文稿.md').write_text('new tree', encoding='utf-8')
    second = run(2)
    assert second['coverage'][0]['lastScan'] == original_date, 'Unexpected full baseline scan on restart'
    with sqlite3.connect(data / 'files.sqlite') as db:
        paths = {row[0] for row in db.execute('SELECT path FROM files')}
    assert str(root / '旧文件.txt') not in paths
    assert str(root / '子目录') not in paths
    assert str(root / '子目录/初稿.md') not in paths
    assert str(root / '改名文件.txt') in paths
    assert str(root / '重命名目录/新增文件.txt') in paths
    assert str(root / '新目录/移动后的文稿.md') in paths
    third = run(3)
    assert third['coverage'][0]['lastScan'] == original_date
    assert third['count'] == second['count']
    catalog_path = data / 'index-state.json'
    catalog = json.loads(catalog_path.read_text())
    assert catalog['checkpoint'] > 0
    catalog['roots'][str(root)]['state'] = 'interrupted'
    catalog_path.write_text(json.dumps(catalog))
    fourth = run(4)
    assert fourth['coverage'][0]['lastScan'] > original_date
    assert fourth['coverage'][0]['state'] == 'ready'
    root.rename(base / 'disconnected')
    fifth = run(5)
    assert fifth['coverage'][0]['state'] == 'offline'
    assert fifth['coverage'][0]['lastScan'] == fourth['coverage'][0]['lastScan']
    (base / 'disconnected').rename(root)
    sixth = run(6)
    assert sixth['coverage'][0]['state'] == 'ready'
    assert sixth['coverage'][0]['lastScan'] > fourth['coverage'][0]['lastScan']
    print('PASS: offline create/rename/delete, moved directory, unchanged restart without full scan, interrupted-baseline recovery, disconnected/reconnected roots, persisted event cursor', flush=True)
