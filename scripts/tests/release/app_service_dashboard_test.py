"""验证应用服务看板生成器与 D1 表结构、遥测枚举保持一致。"""

import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
GENERATOR = ROOT / 'scripts/release/app_service_dashboard.py'
MIGRATIONS = ROOT / 'services/app_service/migrations'
SCHEMA = ROOT / 'docs/contracts/app-service.schema.json'
ACCOUNT = '0' * 32
DATABASE = '00000000-0000-4000-8000-000000000000'
VARIABLES = re.compile(r'\$\{(__from|__to|platform:sqlstring|channel:sqlstring)\}')

spec = importlib.util.spec_from_file_location('app_service_dashboard', GENERATOR)
dashboard = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(dashboard)


def all_panels(dash):
    for panel in dash['panels']:
        yield panel
        yield from panel.get('panels', [])


def queries(dash):
    for panel in all_panels(dash):
        for target in panel.get('targets', []):
            yield panel['title'], target


class AppServiceDashboardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dash = dashboard.build(ACCOUNT, DATABASE)

    def test_rejects_missing_or_malformed_ids(self):
        for account, database in ((None, DATABASE), (ACCOUNT, ''), ('x' * 32, DATABASE),
                                  (ACCOUNT, DATABASE + "' OR 1")):
            with self.assertRaises(ValueError):
                dashboard.build(account, database)

    def test_cli_requires_ids_and_prints_no_target(self):
        result = subprocess.run([sys.executable, GENERATOR], capture_output=True, text=True,
                                env={'PATH': '', 'PYTHONDONTWRITEBYTECODE': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('账号 ID', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_output_is_deterministic_and_targets_only_given_database(self):
        self.assertEqual(json.dumps(self.dash), json.dumps(dashboard.build(ACCOUNT, DATABASE)))
        urls = {target['url'] for _, target in queries(self.dash)}
        self.assertEqual(urls, {f'https://api.cloudflare.com/client/v4/accounts/{ACCOUNT}'
                                f'/d1/database/{DATABASE}/query'})
        for _, target in queries(self.dash):
            self.assertEqual(target['datasource'], {'type': 'yesoreyeram-infinity-datasource', 'uid': 'ubaa-d1'})

    def test_layout_has_unique_ids_and_no_overlap(self):
        ids = [panel['id'] for panel in all_panels(self.dash)]
        self.assertEqual(len(ids), len(set(ids)))
        cells = {}
        for panel in all_panels(self.dash):
            grid = panel['gridPos']
            self.assertLessEqual(grid['x'] + grid['w'], 24, panel['title'])
            for x in range(grid['x'], grid['x'] + grid['w']):
                for y in range(grid['y'], grid['y'] + grid['h']):
                    self.assertNotIn((x, y), cells, f"{panel['title']} 与 {cells.get((x, y))} 重叠")
                    cells[(x, y)] = panel['title']

    def test_multi_column_queries_keep_declared_order(self):
        for panel in all_panels(self.dash):
            names = [column['text'] for target in panel.get('targets', []) for column in target['columns']]
            if len(names) > 1:
                organize = panel['transformations'][0]
                self.assertEqual(organize['id'], 'organize')
                self.assertEqual(list(organize['options']['indexByName']), names, panel['title'])

    def test_every_query_runs_on_migrated_schema(self):
        self.assertGreaterEqual(sqlite3.sqlite_version_info, (3, 38), '需要支持 unixepoch 的 SQLite')
        db = sqlite3.connect(':memory:')
        for migration in sorted(MIGRATIONS.glob('*.sql')):
            db.executescript(migration.read_text(encoding='utf-8'))
        now = int(time.time() * 1000)
        values = {'__from': str(now - 30 * 86_400_000), '__to': str(now),
                  'platform:sqlstring': "'ohos'", 'channel:sqlstring': "'app_gallery'"}
        for title, target in queries(self.dash):
            body = json.loads(target['url_options']['data'])
            self.assertEqual(list(body), ['sql'])
            leftover = VARIABLES.sub('', body['sql'])
            self.assertNotIn('${', leftover, title)
            sql = VARIABLES.sub(lambda match: values[match[1]], body['sql'])
            with self.subTest(panel=title):
                cursor = db.execute(sql)
                selected = [column[0] for column in cursor.description]
                declared = [column['selector'] for column in target['columns']]
                self.assertEqual(set(declared) - set(selected), set())

    def test_feature_labels_cover_schema(self):
        schema = json.loads(SCHEMA.read_text(encoding='utf-8'))
        features = set(schema['$defs']['feature']['enum'])
        self.assertEqual(features, {key for key, _ in dashboard.FEATURES})


if __name__ == '__main__':
    unittest.main()
