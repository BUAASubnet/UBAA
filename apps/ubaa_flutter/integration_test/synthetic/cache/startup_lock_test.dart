import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
  });
  testWidgets('真实 FFI 等待另一进程持锁时 UI 可绘制并可在解锁后重试', (tester) async {
    const path = String.fromEnvironment('UBAA_STARTUP_LOCK_DIR');
    expect(path, isNotEmpty, reason: '通过已登记的外部持锁夹具运行');
    final directory = Directory(path);
    debugPrint('App 夹具：${path.split('/').last}');
    Future<void> waitFor(String name) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      final marker = File('${directory.path}/$name');
      while (!await marker.exists()) {
        if (DateTime.now().isAfter(deadline)) throw StateError('合成持锁夹具未响应');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    BridgeInitializationFailure? observed;
    String? unexpectedType;
    try {
      await directory.create(recursive: true);
      await File('${directory.path}/.session.lock').writeAsString('');
      await File('${directory.path}/request-lock').writeAsString('lock');
      await tester.runAsync(() => waitFor('holder-ready'));
      await tester.pumpWidget(
        UbaaAppHost(
          backendFactory: () async {
            try {
              return await BridgeBackend.open(directory.path);
            } on BridgeInitializationError catch (error) {
              observed = error.failure;
              return const UnavailableBackend(
                failure: InitializationFailure.resourceBusy,
              );
            } on Object catch (error) {
              unexpectedType = error.runtimeType.toString();
              rethrow;
            }
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('正在打开本地数据…'), findsOneWidget);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 8),
      );
      expect(unexpectedType, isNull);
      expect(observed, BridgeInitializationFailure.resourceBusy);
      expect(find.textContaining('其他实例正在使用'), findsOneWidget);
      await File('${directory.path}/release-request').writeAsString('release');
      await tester.runAsync(() => waitFor('holder-released'));
      await tester.tap(find.text('重新打开'));
      await tester.pumpAndSettle();
      expect(find.text('重新打开'), findsNothing);
      expect(find.text('记住密码'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await File('${directory.path}/release-request').writeAsString('release');
    }
  }, skip: !Platform.isMacOS && !Platform.isLinux);
}
