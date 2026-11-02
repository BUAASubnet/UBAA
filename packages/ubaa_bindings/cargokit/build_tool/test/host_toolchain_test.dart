import 'package:build_tool/src/builder.dart';
import 'package:build_tool/src/cargo.dart';
import 'package:build_tool/src/options.dart';
import 'package:build_tool/src/rustup.dart';
import 'package:build_tool/src/target.dart';
import 'package:build_tool/src/util.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<List<List<String>>> build({
  required String host,
  required List<String> installed,
  String requested = '1.95.0',
  String target = 'x86_64-pc-windows-msvc',
}) async {
  final selected = '$requested-$host';
  final toolchains = List<String>.of(installed);
  final components = {
    for (final name in installed) name: <String>[host]
  };
  final calls = <List<String>>[];
  testRunCommandOverride = (args) {
    expect(args.executable, 'rustup');
    calls.add(args.arguments);
    switch (args.arguments) {
      case ['show']:
        return TestRunCommandResult(stdout: 'Default host: $host\r\n');
      case ['toolchain', 'list']:
        return TestRunCommandResult(stdout: '${toolchains.join('\n')}\n');
      case ['toolchain', 'install', final name]:
        // 模拟 Rustup 为无后缀名称补默认主机，安装后只列完整名称。
        final resolved = name == requested ? selected : name;
        toolchains.add(resolved);
        components[resolved] = [host];
        return TestRunCommandResult();
      case ['target', 'list', '--toolchain', final name, '--installed']:
        return TestRunCommandResult(
            stdout: '${(components[name] ?? []).join('\n')}\n');
      case ['target', 'add', '--toolchain', final name, final added]:
        expect(name, selected, reason: '目标组件必须安装到默认主机工具链');
        components[name]!.add(added);
        return TestRunCommandResult();
      case ['component', 'add', 'rust-src', '--toolchain', final name]:
        expect(name, selected);
        return TestRunCommandResult();
      case ['run', _, 'cargo', ...]:
        return TestRunCommandResult();
      default:
        throw StateError('未预期调用：${args.arguments}');
    }
  };
  final rustup = Rustup();
  final options = CargokitCrateOptions.parse(loadYamlNode('''
cargo:
  debug:
    toolchain: $requested
    extra_flags: [--locked]
'''));
  final builder = RustBuilder(
    target: Target.all.firstWhere((entry) => entry.rust == target),
    environment: BuildEnvironment(
      configuration: BuildConfiguration.debug,
      crateOptions: options,
      targetTempDir: '构建 空格',
      manifestDir: '工程 空格',
      crateInfo: CrateInfo(packageName: 'test-crate'),
      isAndroid: false,
    ),
  );
  builder.prepare(rustup);
  await builder.build();
  expect(calls.last.take(5), ['run', selected, 'cargo', 'rustc', '--locked']);
  expect(calls.last, containsAllInOrder(['--target', target]));
  expect(rustup.resolveToolchain(requested), selected);
  expect(rustup.installedTargets(requested), contains(target));
  return calls;
}

void main() {
  const msvc = 'x86_64-pc-windows-msvc';
  const gnu = 'x86_64-pc-windows-gnu';
  tearDown(() => testRunCommandOverride = null);

  for (final installed in [
    ['1.95.0-$gnu', '1.95.0-$msvc'],
    ['1.95.0-$msvc', '1.95.0-$gnu'],
  ]) {
    test('GNU/MSVC 列表顺序不改变默认主机：${installed.first}', () async {
      final calls = await build(host: msvc, installed: installed);
      expect(
          calls.where((args) => args.take(2).join(' ') == 'toolchain install'),
          isEmpty);
    });
  }

  test('Rustup 默认 GNU 主机独立于 Dart 平台和 Cargo 的 MSVC 目标', () async {
    await build(host: gnu, installed: ['1.95.0-$msvc', '1.95.0-$gnu']);
  });

  for (final installed in [
    ['1.95.0-aarch64-pc-windows-msvc'],
    <String>[],
  ]) {
    test('当前主机缺失时安装并重查，不沿用其他架构：$installed', () async {
      final calls = await build(host: msvc, installed: installed);
      expect(calls, contains(equals(['toolchain', 'install', '1.95.0-$msvc'])));
      expect(calls.where((args) => args.join(' ') == 'toolchain list').length,
          greaterThanOrEqualTo(2));
      expect(
          calls,
          contains(equals([
            'target',
            'list',
            '--toolchain',
            '1.95.0-$msvc',
            '--installed'
          ])));
    });
  }

  test('macOS 主机编译 iOS 时只给主机工具链安装目标组件', () async {
    const host = 'aarch64-apple-darwin';
    final calls = await build(
      host: host,
      installed: ['1.95.0-x86_64-apple-darwin', '1.95.0-$host'],
      target: 'aarch64-apple-ios',
    );
    expect(
        calls,
        contains(equals([
          'target',
          'add',
          '--toolchain',
          '1.95.0-$host',
          'aarch64-apple-ios'
        ])));
    expect(calls.last, containsAllInOrder(['--crate-type', 'staticlib']));
  });

  for (final channel in ['stable', 'beta', 'nightly']) {
    test('$channel 保留通道行为并选择默认主机', () async {
      final calls = await build(
        host: msvc,
        installed: ['$channel-$gnu', '$channel-$msvc'],
        requested: channel,
      );
      if (channel == 'nightly') {
        expect(
            calls,
            contains(equals([
              'component',
              'add',
              'rust-src',
              '--toolchain',
              'nightly-$msvc'
            ])));
      }
    });
  }

  test('默认主机解析失败必须报错，禁止回退到列表第一项', () {
    testRunCommandOverride = (args) => TestRunCommandResult(
            stdout: switch (args.arguments) {
          ['show'] => '没有默认主机字段',
          ['toolchain', 'list'] => '1.95.0-$gnu\n',
          ['target', 'list', ...] => '$gnu\n',
          _ => throw StateError('未预期调用：${args.arguments}'),
        });
    expect(Rustup.new, throwsStateError);
  });

  test('安装返回成功但重查仍缺默认主机时不得伪造已安装记录', () {
    testRunCommandOverride = (args) => TestRunCommandResult(
            stdout: switch (args.arguments) {
          ['show'] => 'Default host: $msvc\n',
          ['toolchain', 'list'] => '1.95.0-$gnu\n',
          ['target', 'list', ...] => '$gnu\n',
          ['toolchain', 'install', _] => '',
          _ => throw StateError('未预期调用：${args.arguments}'),
        });
    final rustup = Rustup();
    expect(() => rustup.installToolchain('1.95.0'), throwsStateError);
  });
}
