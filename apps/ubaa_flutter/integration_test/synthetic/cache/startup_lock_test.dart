import 'dart:async';
import 'dart:convert';
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
    const encoded = String.fromEnvironment('UBAA_STARTUP_LOCK_HOLDER');
    expect(encoded, isNotEmpty, reason: '通过已登记的外部持锁夹具运行');
    final script = utf8.decode(base64Decode(encoded));
    // 目录由应用合法创建，宿主终端不访问受保护的应用容器。
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-startup-lock-',
    );
    Process? holder;
    StreamIterator<String>? messages;
    Future<String> nextMessage() async {
      final available = await messages!.moveNext().timeout(
        const Duration(seconds: 10),
      );
      if (!available) throw StateError('合成持锁进程提前退出');
      return messages!.current;
    }

    BridgeInitializationFailure? observed;
    String? unexpectedType;
    try {
      await tester.runAsync(() async {
        holder = await Process.start('perl', [
          '-e',
          script,
          '${directory.path}/.session.lock',
        ]);
        messages = StreamIterator(
          holder!.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        holder!.stderr.transform(utf8.decoder).listen(debugPrint);
        expect(holder!.pid, isNot(pid), reason: '必须由另一操作系统进程持锁');
        expect(await nextMessage(), 'locked:${holder!.pid}');
      });
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(observed, isNull, reason: '锁等待期间必须先绘制启动画面');
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 8),
      );
      expect(unexpectedType, isNull);
      expect(observed, BridgeInitializationFailure.resourceBusy);
      expect(find.textContaining('其他实例正在使用'), findsOneWidget);
      await tester.runAsync(() async {
        holder!.stdin.writeln('release');
        await holder!.stdin.flush();
        expect(await nextMessage(), 'released');
        expect(await holder!.exitCode, 0);
      });
      await tester.tap(find.text('重新打开'));
      await tester.pumpAndSettle();
      expect(find.text('重新打开'), findsNothing);
      expect(find.text('记住密码'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      holder?.kill();
      await messages?.cancel();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isMacOS && !Platform.isLinux);
}
