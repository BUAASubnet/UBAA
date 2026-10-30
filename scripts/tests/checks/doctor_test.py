"""doctor 必须把缺失或不符的必需工具判为失败，可选项只提示。"""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'bootstrap'))
import doctor


class DoctorTest(unittest.TestCase):
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
