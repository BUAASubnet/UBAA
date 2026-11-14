"""验证应用服务看板生成器与 PostgreSQL 表结构、遥测枚举保持一致。"""

import importlib.util
from datetime import datetime, timedelta, timezone
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
VARIABLES = re.compile(r'\$\{(__from|__to|platform:csv|channel:csv)\}')
TIME = re.compile(r'\$\{(__from|__to)\}')

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
        cls.dash = dashboard.build()

    def test_native_datasource_and_deterministic_output(self):
        self.assertEqual(self.dash, dashboard.build())
        for _, target in queries(self.dash):
            self.assertEqual(target['datasource']['uid'], 'ubaa-postgres')
            self.assertIn('rawSql', target)

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

    def test_feature_labels_cover_schema(self):
        schema = json.loads(SCHEMA.read_text(encoding='utf-8'))
        features = set(schema['$defs']['feature']['enum'])
        self.assertEqual(features, {key for key, _ in dashboard.FEATURES})


if __name__ == '__main__':
    unittest.main()
