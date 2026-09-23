import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('系统私有目录不依赖 iOS 环境变量，可保存独立合成文件', (tester) async {
    await initializePrivateDirectory();
    final root = Directory(defaultConfigDirectory());
    expect(root.isAbsolute, isTrue);
    expect(root.path.split(Platform.pathSeparator).last, 'UBAA');
    final own = Directory(
      '${root.path}/native-path-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await own.create(recursive: true);
      final file = File('${own.path}/probe');
      await file.writeAsString('合成目录探测');
      expect(await file.readAsString(), '合成目录探测');
      expect(defaultConfigDirectory(), root.path);
    } finally {
      if (await own.exists()) await own.delete(recursive: true);
    }
  });
  testWidgets('系统安全材料可重开读取且清理可核实', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('安全存储合成验证'))),
      ),
    );
    final key = 'probe.${DateTime.now().microsecondsSinceEpoch}';
    final first = SecureMaterialStore(transport: _ProbeTransport());
    await first.probe();
    expect(first.isAvailable, isTrue);
    var completed = false;
    try {
      await first.write(key, '仅用于本次测试的合成材料');
      final reopened = SecureMaterialStore(transport: _ProbeTransport());
      await reopened.probe();
      expect(await reopened.read(key), '仅用于本次测试的合成材料');
      await reopened.delete(key);
      expect(await first.read(key), isNull);
      completed = true;
    } finally {
      try {
        await first.delete(key);
      } on SecureMaterialException {
        if (completed) rethrow;
        debugPrint('安全材料合成探测清理失败，保留首个错误');
      }
    }
  });
}

// 原生探测只输出操作枚举与整数状态，不输出平台错误正文或材料键值。
class _ProbeTransport implements SecureMaterialTransport {
  final _native = const PlatformSecureMaterialTransport();
  Future<T> _call<T>(String operation, Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      final status = error.details;
      debugPrint('安全材料原生探测：$operation，状态=${status is int ? status : '未提供'}');
      rethrow;
    }
  }

  @override
  Future<String?> read(String key) => _call('read', () => _native.read(key));
  @override
  Future<void> write(String key, String value) =>
      _call('write', () => _native.write(key, value));
  @override
  Future<void> delete(String key) => _call('delete', () => _native.delete(key));
}
