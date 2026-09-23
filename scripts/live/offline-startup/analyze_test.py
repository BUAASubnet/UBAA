"""统计合同：不改变分母，不以失败样本或宿主装配时间填充进程指标。"""
import unittest
from analyze import summarize, validate


def sample(delay):
    return {"process_start_us": 1000000, "business_writes": 0, "times": {
        "dart_main_us": 1010000, "home_build_end_us": 1020000,
        "home_frame_us": 1030000, "cache_visible_us": 1000000 + delay * 1000,
        "recovery_rpc_started_us": 1040000,
    }}


class StatisticsContract(unittest.TestCase):
    def test_计划30次只执行2次时保留未执行分母(self):
        result = summarize([sample(100), sample(120)], planned=30)
        self.assertEqual(result['planned'], 30)
        self.assertEqual(result['not_started'], 28)
        self.assertFalse(result['metrics']['cache_visible']['population_complete'])
        self.assertEqual(result['metrics']['cache_visible']['missing'], 28)

    def test_五来源完成不能标记完整首页完成(self):
        value = sample(100)
        value['times']['all_refresh_done_us'] = 2000000
        value['outcomes'] = {key: {'complete': True, 'error': None}
                             for key in ('schedule', 'signin', 'spoc', 'judge', 'ygdk')}
        self.assertIn('incomplete_home_coverage', validate(value))
        for key in ('bykcChosen', 'cgyyOrders', 'currentWeek', 'gradeCheck'):
            value['outcomes'][key] = {'finished': True, 'error': None}
        value['outcomes']['gradeCheck']['check_complete'] = True
        self.assertNotIn('incomplete_home_coverage', validate(value))
        value['outcomes']['gradeCheck']['error'] = 'internalError'
        self.assertIn('incomplete_home_coverage', validate(value))

    def test_30次使用原分母和nearest_rank(self):
        values = [sample(100 + i) for i in range(30)]
        result = summarize(values)
        self.assertEqual(result["metrics"]["cache_visible"]["median_ms"], 114.5)
        self.assertEqual(result["metrics"]["cache_visible"]["p95_ms"], 128)
        self.assertEqual(result["fully_refreshed"], 0)
        self.assertEqual(result["metrics"]["all_refresh_done"]["missing"], 30)

    def test_缺失内核时间及时间倒退不能换用Dart起点(self):
        missing = sample(100)
        del missing["process_start_us"]
        reversed_clock = sample(100)
        reversed_clock["times"]["dart_main_us"] = 10
        result = summarize([sample(100), missing, reversed_clock])
        self.assertEqual(result["samples"], 3)
        self.assertEqual(result["valid"], 1)
        self.assertEqual(result["metrics"]["cache_visible"]["missing"], 2)

    def test_写入尝试和缺失缓存均拒绝作为有效启动(self):
        value = sample(100)
        value["business_writes"] = 1
        del value["times"]["cache_visible_us"]
        self.assertIn("business_write_attempt", validate(value))
        self.assertIn("missing:cache_visible_us", validate(value))

    def test_被中断时缺少写入计数不能误报已发生写入(self):
        value = sample(100)
        value["business_writes"] = None
        self.assertIn("missing_business_write_count", validate(value))
        self.assertNotIn("business_write_attempt", validate(value))

    def test_成本按认证上游缓存与调度等待分列(self):
        value = sample(100)
        value['operations'] = [
            {'operation': 'routeSettings', 'phase': 'authentication',
             'start_us': 1000000, 'end_us': 1001000, 'success': True},
            {'operation': 'read.schedule', 'phase': 'upstream',
             'start_us': 1002000, 'end_us': 1005000, 'success': True,
             'origin': 'online'},
        ]
        value['scheduler_traces'] = [
            {'kind': 'completed', 'wait_us': 2000, 'run_us': 3000},
        ]
        result = summarize([value])
        self.assertEqual(result['cost']['phase']['authentication']['count'], 1)
        self.assertEqual(result['cost']['phase']['upstream']['median_ms'], 3)
        self.assertEqual(result['cost']['scheduler']['wait_ms']['median_ms'], 2)
        self.assertEqual(result['cost']['origin_counts']['online'], 1)


if __name__ == "__main__":
    unittest.main()
