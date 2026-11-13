import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/runtime.dart' show RequiredRecoveryOperation;
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../../support/rust_library.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 FRB/Core 打开本地首页并将缺会话结果显示为需要登录', (tester) async {
    await tester.runAsync(() async {
      await initializeRustLibrary();
      final directory = await Directory.systemTemp.createTemp(
        'ubaa-host-smoke-',
      );
      final accounts = await fixtures.savedAccounts();
      final account = (await accounts.read())!.account!;
      _ObservedBridgeBackend? backend;
      try {
        await tester.pumpWidget(
          UbaaFlutterApp(
            backendFactory: () async {
              final client = await BridgeClient.open(configDir: directory.path);
              await client.setDefaultRoutePolicy(
                policy: BridgeRoutePolicy.direct,
              );
              return backend = _ObservedBridgeBackend(client, directory.path);
            },
            localAccountStore: accounts,
            credentialVault: MemoryCredentialVault(),
          ),
        );
        final waiting = Stopwatch()..start();
        while (!(backend?.firstRecovery.isCompleted ?? false) ||
            find.byTooltip('完成登录').evaluate().isEmpty) {
          if (waiting.elapsed > const Duration(seconds: 10)) {
            throw TimeoutException(
              '首页首帧后的会话恢复未完成',
              const Duration(seconds: 10),
            );
          }
          // 同时等待 Core 结果和宿主发布恢复状态，覆盖首帧与共享账号检查后的异步交付。
          await Future<void>.delayed(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();

        expect(
          backend!.recoveryFailure?.code,
          UbaaErrorCode.authenticationRequired,
        );
        expect(backend!.recoveryFailure?.resolvedRoute, ConnectionMode.direct);
        final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
        expect(shell.user?.username, account.username);
        expect(shell.connectionStatus, '需要登录，当前页面会保留');
        expect(find.byTooltip('完成登录'), findsOneWidget);
        expect(
          (await backend!.cacheUsage(accountId: account.id)).accountId,
          account.id,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await backend?.deactivateOfflineAccount();
        await backend?.dispose();
        await directory.delete(recursive: true);
      }
    });
  });
}

/// 只记录真实适配器返回的结果；认证恢复和缓存读取仍经过原生 Core。
class _ObservedBridgeBackend extends BridgeBackend {
  _ObservedBridgeBackend(BridgeClient client, String directory)
    : super(client, configDirectory: directory);

  final firstRecovery = Completer<void>();
  BackendException? recoveryFailure;

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    // 覆盖磁盘读取晚于当前帧完成的启动过程。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return super.readCachedHome(policy);
  }

  @override
  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  ) {
    final operation = super.startTargetRecovery(target, limit);
    final result = () async {
      try {
        return await operation.result;
      } on BackendException catch (error) {
        recoveryFailure = error;
        rethrow;
      } finally {
        if (!firstRecovery.isCompleted) firstRecovery.complete();
      }
    }();
    return _ObservedOperation(operation, result);
  }
}

class _ObservedOperation implements RequiredRecoveryOperation {
  _ObservedOperation(this.operation, this.result);
  final RequiredRecoveryOperation operation;
  @override
  final Future<RecoveredRouteSession> result;
  @override
  void cancel() => operation.cancel();
  @override
  void dispose() => operation.dispose();
}
