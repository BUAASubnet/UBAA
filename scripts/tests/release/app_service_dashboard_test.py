"""验证应用服务看板生成器与 D1 表结构、遥测枚举保持一致。"""

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

    def migrated(self):
        self.assertGreaterEqual(sqlite3.sqlite_version_info, (3, 38), '需要支持 unixepoch 的 SQLite')
        db = sqlite3.connect(':memory:')
        for migration in sorted(MIGRATIONS.glob('*.sql')):
            db.executescript(migration.read_text(encoding='utf-8'))
        db.execute("INSERT INTO active_days VALUES (date('now','+8 hours'),'a','','2.0.0','ohos','app_gallery','',0,1)")
        db.execute("INSERT INTO active_days VALUES (date('now','+8 hours'),'b','','2.0.0','android','github','',0,1)")
        return db

    def run_all(self, db, values):
        now = int(time.time() * 1000)
        values = {'__from': str(now - 30 * 86_400_000), '__to': str(now), **values}
        for title, target in queries(self.dash):
            body = json.loads(target['url_options']['data'])
            self.assertEqual(list(body), ['sql'])
            leftover = VARIABLES.sub('', body['sql'])
            self.assertNotIn('${', leftover, title)
            sql = VARIABLES.sub(lambda match: values.get(match[1], match[0]), body['sql'])
            with self.subTest(panel=title):
                cursor = db.execute(sql)
                selected = [column[0] for column in cursor.description]
                declared = [column['selector'] for column in target['columns']]
                self.assertEqual(set(declared) - set(selected), set())

    def devices(self, db, values):
        _, target = next(item for item in queries(self.dash) if item[0] == '平台分布')
        sql = json.loads(target['url_options']['data'])['sql']
        now = int(time.time() * 1000)
        values = {'__from': str(now - 86_400_000), '__to': str(now), **values}
        return dict(db.execute(VARIABLES.sub(lambda match: values.get(match[1], match[0]), sql)).fetchall())

    def test_every_query_runs_on_migrated_schema(self):
        self.run_all(self.migrated(), {'platform:csv': 'ohos', 'channel:csv': 'app_gallery'})

    def test_filters_select_given_values(self):
        db = self.migrated()
        self.assertEqual(self.devices(db, {'platform:csv': 'ohos', 'channel:csv': 'app_gallery,github'}),
                         {'HarmonyOS': 1})
        self.assertEqual(self.devices(db, {'platform:csv': 'android,ohos', 'channel:csv': 'github'}),
                         {'Android': 1})

    def test_public_dashboard_without_variables_shows_everything(self):
        # 公开面板不替换模板变量；变量原样保留或为空时都按“全部”处理。
        db = self.migrated()
        self.run_all(db, {})
        self.assertEqual(self.devices(db, {}), {'HarmonyOS': 1, 'Android': 1})
        self.assertEqual(self.devices(db, {'platform:csv': '', 'channel:csv': ''}),
                         {'HarmonyOS': 1, 'Android': 1})

    def test_feature_labels_cover_schema(self):
        schema = json.loads(SCHEMA.read_text(encoding='utf-8'))
        features = set(schema['$defs']['feature']['enum'])
        self.assertEqual(features, {key for key, _ in dashboard.FEATURES})

    def curve_sql(self, title, start, end, platform='', channel=''):
        _, target = next(item for item in queries(self.dash) if item[0] == title)
        sql = json.loads(target['url_options']['data'])['sql']
        values = {'__from': str(int(start.timestamp() * 1000)),
                  '__to': str(int(end.timestamp() * 1000)),
                  'platform:csv': platform, 'channel:csv': channel}
        return VARIABLES.sub(lambda match: values[match[1]], sql)

    def test_monthly_curves_have_bounded_work(self):
        # 只有一天的 1,440 分钟数据，查看整月时也不能为每个横轴点重扫明细。
        start = datetime(2025, 1, 1, tzinfo=timezone(timedelta(hours=8)))
        db = self.migrated()
        for minute in range(1440):
            at = (start + timedelta(minutes=minute)).strftime('%Y-%m-%dT%H:%M')
            for event in ('feature_loaded', 'auth_started'):
                db.execute('INSERT INTO minute_counts VALUES (?, ?, ?, ?, ?, ?, ?)',
                           (at, event, 'schedule', 'success', 'android', 'github', 1))
        for title in ('功能使用曲线', '登录曲线'):
            with self.subTest(panel=title):
                steps = 0

                def progress():
                    nonlocal steps
                    steps += 1000
                    return int(steps > 2_000_000)

                db.set_progress_handler(progress, 1000)
                try:
                    rows = db.execute(self.curve_sql(title, start, start + timedelta(days=30))).fetchall()
                except sqlite3.OperationalError as error:
                    self.fail(f'{title} 超出 200 万 SQLite 指令预算：{error}')
                finally:
                    db.set_progress_handler(None, 0)
                self.assertEqual(len(rows), 721)
                self.assertEqual(sum(row[1] for row in rows), 1440)
                self.assertTrue(all(value == 0 for row in rows[24:] for value in row[1:]))

    def test_curve_buckets_filters_and_zero_filling(self):
        start = datetime(2025, 1, 1, 23, 57, tzinfo=timezone(timedelta(hours=8)))
        db = self.migrated()
        samples = []
        for minute, feature, platform, channel, count in (
            (-1, 'schedule', 'android', 'github', 100),
            (0, 'schedule', 'android', 'github', 2),
            (3, 'schedule', 'android', 'github', 3),
            (4, 'classroom', 'android', 'github', 5),
            (5, 'schedule', 'ios', 'app_store', 7),
            (6, 'schedule', 'android', 'app_store', 11),
            (300, 'schedule', 'android', 'github', 13),
            (301, 'schedule', 'android', 'github', 17),
        ):
            at = start + timedelta(minutes=minute)
            for event in ('feature_loaded', 'auth_started', 'auth_succeeded', 'auth_failed'):
                db.execute('INSERT INTO minute_counts VALUES (?, ?, ?, ?, ?, ?, ?)',
                           (at.strftime('%Y-%m-%dT%H:%M'), event, feature, 'success', platform, channel, count))
            samples.append((at, feature, platform, channel, count))
        for duration, bucket in ((300, 1), (1440, 5), (4320, 10), (43200, 60), (57600, 1440)):
            end = start + timedelta(minutes=duration)
            for platform, channel in (('', ''), ('android', 'github')):
                for title in ('功能使用曲线', '登录曲线'):
                    with self.subTest(panel=title, duration=duration, platform=platform):
                        rows = db.execute(self.curve_sql(title, start, end, platform, channel)).fetchall()
                        expected = {row[0]: [0] * (len(row) - 1) for row in rows}
                        width = bucket * 60_000
                        offset = 8 * 3_600_000
                        first = (int(start.timestamp() * 1000) + offset) // width * width - offset
                        last = (int(end.timestamp() * 1000) + offset) // width * width - offset
                        self.assertEqual(list(expected), list(range(first, last + 1, width)))
                        for at, feature, plat, chan, count in samples:
                            if not start <= at <= end or (platform and plat != platform) or (channel and chan != channel):
                                continue
                            t = (int(at.timestamp() * 1000) + offset) // width * width - offset
                            if title == '功能使用曲线':
                                expected[t][0 if feature == 'schedule' else -1] += count
                            else:
                                expected[t] = [value + count for value in expected[t]]
                        self.assertEqual(rows, [(t, *values) for t, values in expected.items()])


if __name__ == '__main__':
    unittest.main()
