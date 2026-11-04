import 'package:build_tool/src/builder.dart';
import 'package:build_tool/src/cargo.dart';
import 'package:build_tool/src/options.dart';
import 'package:build_tool/src/rustup.dart';
import 'package:build_tool/src/target.dart';
import 'package:build_tool/src/util.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  tearDown(() => testRunCommandOverride = null);

  test('精确版本沿用已安装工具链并传给实际 cargo 调用', () async {
    final calls = <List<String>>[];
    testRunCommandOverride = (args) {
      expect(args.executable, 'rustup');
      calls.add(args.arguments);
      return TestRunCommandResult(
          stdout: switch (args.arguments) {
        ['show'] => 'Default host: x86_64-pc-windows-msvc\n',
        ['toolchain', 'list'] => 'stable-x86_64-pc-windows-msvc (default)\n'
            '1.95.0-x86_64-pc-windows-msvc\n',
        ['target', 'list', '--toolchain', _, '--installed'] =>
          'x86_64-pc-windows-msvc\n',
        ['run', _, 'cargo', ...] => '',
        _ => throw StateError('不应安装或修改工具链：${args.arguments}'),
      });
    };
    final options = CargokitCrateOptions.parse(loadYamlNode('''
cargo:
  debug:
    toolchain: 1.95.0
    extra_flags: [--locked]
'''));
    final builder = RustBuilder(
      target: Target(rust: 'x86_64-pc-windows-msvc'),
      environment: BuildEnvironment(
        configuration: BuildConfiguration.debug,
        crateOptions: options,
        targetTempDir: 'build',
        manifestDir: 'crate',
        crateInfo: CrateInfo(packageName: 'test-crate'),
        isAndroid: false,
      ),
    );
    builder.prepare(Rustup());
    await builder.build();
    expect(calls.last.take(5),
        ['run', '1.95.0-x86_64-pc-windows-msvc', 'cargo', 'rustc', '--locked']);
    expect(calls.last, containsAll(['--crate-type', 'cdylib']));
  });

  test('保留上游通道并拒绝模糊或非法版本', () {
    for (final name in ['stable', 'beta', 'nightly', '1.95.0']) {
      expect(() => CargoBuildOptions.parse(loadYamlNode('toolchain: $name')),
          returnsNormally);
    }
    for (final name in ['1.95', 'latest', '1.95.0-typo', '../1.95.0']) {
      expect(() => CargoBuildOptions.parse(loadYamlNode('toolchain: $name')),
          throwsA(isA<SourceSpanException>()));
    }
  });
}
