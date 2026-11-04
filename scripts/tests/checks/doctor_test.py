"""doctor 必须把缺失或不符的必需工具判为失败，可选项只提示。"""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'bootstrap'))
import doctor


class DoctorTest(unittest.TestCase):
    def test_质量检查使用进程Bash并保留参数及环境(self):
        environment = {'PATH': '测试PATH'}
        command = ['测试Bash', 'D:/项目 空格/scripts/tools/python.sh', '-c', 'pass']
        pins = doctor.read_values(doctor.ROOT / 'scripts/tools/versions.env')
        with patch.object(doctor, 'bash_command', return_value=command) as bash, \
                patch.object(doctor, 'run', return_value='') as run:
            rows = doctor.collect(environment, pins)
        bash.assert_called_once_with(doctor.ROOT / 'scripts/tools/python.sh', '-c', 'pass', environment=environment)
        self.assertIn(unittest.mock.call(command, env=environment), run.call_args_list)
        self.assertIn(('Python 质量环境', True, '已准备', '已准备'), rows)
        with patch.object(doctor, 'bash_command', side_effect=ValueError('缺少Bash')), \
                patch.object(doctor, 'run', return_value=''):
            self.assertIn(('Python 质量环境', True, '已准备', None), doctor.collect(environment, pins))

    def test_版本比较区分精确锁定与最低版本(self):
        self.assertTrue(doctor.matches('1.51.0', '1.51.0'))
        self.assertFalse(doctor.matches('1.51.0', '1.50.0'))
        self.assertFalse(doctor.matches('1.51.0', None))
        self.assertTrue(doctor.matches('22+', '24'))
        self.assertFalse(doctor.matches('3.11+', '3.9'))

    def test_必需项不符时失败而可选项缺失不失败(self):
        optional_missing = [('just', True, '1.51.0', '1.51.0'), ('DevEco', False, '已配置', None)]
        required_wrong = [('just', True, '1.51.0', '1.40.0')]
        with patch.object(doctor, 'collect', return_value=optional_missing):
            self.assertEqual(doctor.main(), 0)
        with patch.object(doctor, 'collect', return_value=required_wrong):
            self.assertEqual(doctor.main(), 1)


if __name__ == '__main__':
    unittest.main()
