import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

import '../../../test/support/platform/native_materials.dart';
import '../../support/rust_library.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('系统私有目录可首次创建并重开应用服务数据库', (tester) async {
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
      await initializeRustLibrary();
      Future<BridgeAppService> open() => BridgeAppService.open(
        configDir: own.path,
        serviceUrl: 'http://127.0.0.1:9',
        channel: 'github',
        appVersion: '2.0.0+2003',
        platform: BridgeAppServicePlatform.values.byName(
          Platform.operatingSystem,
        ),
        release: false,
        surface: BridgeAppServiceSurface.gui,
        policyVersion: 1,
      );
      final first = await open();
      try {
        expect((await first.state()).available, isTrue);
        await first.setTelemetry(enabled: false);
      } finally {
        first.dispose();
      }
      final reopened = await open();
      try {
        expect((await reopened.state()).telemetryEnabled, isFalse);
        expect(
          await File('${own.path}/app_service.sqlite3').length(),
          greaterThan(0),
        );
      } finally {
        reopened.dispose();
      }
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
    final coordination = await Directory.systemTemp.createTemp(
      'ubaa_synthetic_native_',
    );
    addTearDown(() async => coordination.delete(recursive: true));
    final first = await createNativeTestMaterials(domain: coordination);
    await first.probe();
    expect(first.isAvailable, isTrue);
    var completed = false;
    try {
      await first.write(key, '仅用于本次测试的合成材料');
      final reopened = await createNativeTestMaterials(domain: coordination);
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
  }, skip: Platform.isLinux);
}
