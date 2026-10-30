#!/usr/bin/env python3
"""用实际 CMake 构建验证 OHOS 打包时保留 Rust 动态库名称。"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CARGOKIT_CMAKE = ROOT / 'packages/ubaa_bindings/cargokit/cmake/cargokit.cmake'


class OhosNativeLibraryTest(unittest.TestCase):
    def test_打包文件名与Dart加载的动态库一致(self):
        cmake = shutil.which('cmake')
        self.assertIsNotNone(cmake, '测试需要 CMake')
        for configuration in ['Debug', 'Release']:
            with self.subTest(configuration=configuration), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                cmake_dir = root / 'cargokit/cmake'
                cmake_dir.mkdir(parents=True)
                shutil.copyfile(CARGOKIT_CMAKE, cmake_dir / 'cargokit.cmake')
                (root / 'cargokit/run_build_tool.sh').write_text(
                    '#!/bin/sh\n'
                    'set -eu\n'
                    'mkdir -p "$CARGOKIT_OUTPUT_DIR"\n'
                    'printf "ubaa-rust-library" > "$CARGOKIT_OUTPUT_DIR/libubaa_flutter_bridge.so"\n'
                )
                (root / 'cargokit/run_build_tool.cmd').write_text(
                    '@echo off\n'
                    'if not exist "%CARGOKIT_OUTPUT_DIR%" mkdir "%CARGOKIT_OUTPUT_DIR%"\n'
                    'echo ubaa-rust-library>"%CARGOKIT_OUTPUT_DIR%\\libubaa_flutter_bridge.so"\n'
                )
                (root / 'CMakeLists.txt').write_text(
                    'cmake_minimum_required(VERSION 3.10)\n'
                    'project(ubaa_bindings NONE)\n'
                    'set(CMAKE_SHARED_MODULE_PREFIX "lib")\n'
                    'set(CMAKE_SHARED_MODULE_SUFFIX ".so")\n'
                    'set(OHOS_ARCH "arm64-v8a")\n'
                    'set(FLUTTER_TARGET_PLATFORM "ohos-arm64")\n'
                    'set(TARGET_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/${OHOS_ARCH}")\n'
                    'file(MAKE_DIRECTORY "${TARGET_LIB_DIR}")\n'
                    'include(cargokit/cmake/cargokit.cmake)\n'
                    'apply_cargokit(ubaa_bindings . ubaa_flutter_bridge "")\n'
                )
                build = root / 'build'
                for args in [
                    [cmake, '-S', str(root), '-B', str(build),
                     f'-DCMAKE_BUILD_TYPE={configuration}'],
                    [cmake, '--build', str(build)],
                ]:
                    result = subprocess.run(args, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                packaged = root / 'libs/arm64-v8a/libubaa_flutter_bridge.so'
                self.assertTrue(packaged.is_file(), 'OHOS 包必须保留 Dart 实际加载的动态库名')
                self.assertEqual(packaged.read_bytes(), (build / packaged.name).read_bytes())
                self.assertFalse((packaged.parent / 'libubaa_bindings.so').exists())


if __name__ == '__main__':
    unittest.main()
