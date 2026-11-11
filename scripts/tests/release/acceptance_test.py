"""Release 只复用同一源码树且来源匹配的完整验收。"""
import copy
import importlib.util
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('acceptance', ROOT / 'scripts/release/acceptance.py')
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)

class AcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.run = {'id': 10, 'run_attempt': 2, 'conclusion': 'success', 'event': 'pull_request',
                    'path': '.github/workflows/ci.yml', 'head_sha': 'head'}
        self.record = {'schema': 1, 'repository': 'owner/repo', 'run_id': 10, 'run_attempt': 2,
                       'event': 'pull_request', 'checked_sha': 'synthetic', 'tree': 'same-tree',
                       'pr': 3, 'head_sha': 'head', 'base_sha': 'base'}
        self.pr = {'number': 3, 'merged_at': 'date', 'merge_commit_sha': 'main',
                   'base': {'ref': 'main', 'repo': {'full_name': 'owner/repo'}},
                   'head': {'sha': 'head'}}

    def matches(self):
        return acceptance.matches(self.record, self.run, 'owner/repo', 'main', 'same-tree', self.pr)

    def test_synthetic与main提交不同但完整源码树相同可以复用(self):
        self.assertTrue(self.matches())

    def test_源码与检查输入发生任何树变化都重验(self):
        self.record['tree'] = 'changed-tree'
        self.assertFalse(self.matches())

    def test_失败取消旧运行尝试和错PR均不能复用(self):
        for key, value in [('conclusion', 'failure'), ('conclusion', 'cancelled'),
                           ('run_attempt', 3), ('head_sha', 'other'), ('path', 'other.yml')]:
            saved = copy.deepcopy(self.run)
            self.run[key] = value
            self.assertFalse(self.matches(), key)
            self.run = saved
        for key, value in [('pr', 4), ('schema', 9), ('repository', 'other/repo'),
                           ('run_id', 11), ('checked_sha', ''), ('base_sha', ''), ('event', 'workflow_dispatch')]:
            saved = copy.deepcopy(self.record)
            self.record[key] = value
            self.assertFalse(self.matches(), key)
            self.record = saved
        self.pr['merge_commit_sha'] = 'other'
        self.assertFalse(self.matches())

    def test_主线手动验收必须匹配精确提交(self):
        self.run.update(event='workflow_dispatch', head_sha='main')
        self.record.update(event='workflow_dispatch', checked_sha='main', pr=0)
        self.assertTrue(self.matches())
        self.record['checked_sha'] = 'synthetic'
        self.assertFalse(self.matches())

    def test_发布汇总不接受意外跳过或失败(self):
        jobs = {name: {'result': 'success'} for name in ('metadata', 'store-access', 'acceptance', 'verify')}
        self.assertTrue(acceptance.ready(jobs, False))
        self.assertFalse(acceptance.ready(jobs, True))
        jobs['verify']['result'] = 'skipped'
        self.assertTrue(acceptance.ready(jobs, True))
        self.assertFalse(acceptance.ready(jobs, False))
        for name in ('metadata', 'store-access', 'acceptance'):
            jobs[name]['result'] = 'failure'
            self.assertFalse(acceptance.ready(jobs, True))
            jobs[name]['result'] = 'success'

if __name__ == '__main__':
    unittest.main()
