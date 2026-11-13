"""Linux 命令构建保留编译声明，并从纯 Dart Kernel 生成可执行文件。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('command_build', ROOT / 'scripts/build/command.py')
command = importlib.util.module_from_spec(spec)
spec.loader.exec_module(command)


class CommandBuildTest(unittest.TestCase):
    def test_Kernel保留发布声明且可执行文件不依赖中间产物(self):
        private = ROOT / '.ubaa_local/command_build_tests'
        private.mkdir(parents=True, exist_ok=True)
        for mode in ('debug', 'release'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(dir=private) as folder:
                output = Path(folder)
                environment = {'UBAA_APP_SERVICE_URL': 'https://service.example.invalid',
                               'UBAA_DISTRIBUTION_CHANNEL': 'github'}
                kernels = []

                def compile_step(arguments, actual_environment):
                    self.assertEqual(actual_environment, environment)
                    if arguments[0] == 'c++':
                        return
                    target = Path(arguments[arguments.index('-o') + 1])
                    if arguments[3] == 'kernel':
                        self.assertIn('--packages=.dart_tool/package_config.json', arguments)
                        self.assertIn('apps/ubaa_flutter/bin/ubaa.dart', arguments)
                        self.assertIn(f'-DUBAA_COMMAND_RELEASE={str(mode == "release").lower()}', arguments)
                        self.assertIn('-DUBAA_APP_SERVICE_URL=https://service.example.invalid', arguments)
                        self.assertIn('-DUBAA_DISTRIBUTION_CHANNEL=github', arguments)
                        self.assertTrue(any(value.startswith('-DUBAA_COMMAND_APP_VERSION=')
                                            for value in arguments))
                        target.write_bytes(b'compiled kernel')
                        kernels.append(target)
                    else:
                        self.assertEqual(arguments[3], 'exe')
                        self.assertEqual(len(kernels), 1, 'AOT 编译前必须生成带声明的 Kernel')
                        self.assertEqual(Path(arguments[4]), kernels[0])
                        target.write_bytes(kernels[0].read_bytes())

                with patch.object(command, 'run', side_effect=compile_step), \
                     patch.object(command.subprocess, 'check_output', return_value='-lsecret-1'):
                    command.compile_linux(output, environment, mode, standalone=True)
                self.assertEqual((output / 'ubaa-cli').read_bytes(), b'compiled kernel')
                self.assertTrue(all(not path.exists() for path in kernels))


if __name__ == '__main__':
    unittest.main()
