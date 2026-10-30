import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DemoBackend 驱动官方宿主完成登录交互并显示首页', (tester) async {
    try {
      await tester.pumpWidget(
        UbaaFlutterApp(
          backend: DemoBackend(loginDelay: Duration.zero),
          credentialVault: MemoryCredentialVault(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UBAA 登录'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '2020000000');
      await tester.enterText(find.byType(TextField).at(1), 'demo-password');
      final loginButton = find.widgetWithText(FilledButton, '登录');
      await tester.pump();
      expect(tester.widget<FilledButton>(loginButton).onPressed, isNotNull);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      expect(find.text('今日课表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('真实 FRB/Core 打开本地首页并将缺会话结果显示为需要登录', (tester) async {
    await RustLib.init();
    final directory = await Directory.systemTemp.createTemp('ubaa-host-smoke-');
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
      await tester.pumpAndSettle();
      await backend!.firstRecovery.future.timeout(const Duration(seconds: 10));
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
}

/// 只记录真实适配器返回的结果；认证恢复和缓存读取仍经过原生 Core。
class _ObservedBridgeBackend extends BridgeBackend {
  _ObservedBridgeBackend(BridgeClient client, String directory)
    : super(client, configDirectory: directory);

  final firstRecovery = Completer<void>();
  BackendException? recoveryFailure;

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    try {
      return await super.recoverRequiredSession(feature);
    } on BackendException catch (error) {
      recoveryFailure = error;
      rethrow;
    } finally {
      if (!firstRecovery.isCompleted) firstRecovery.complete();
    }
  }
}
