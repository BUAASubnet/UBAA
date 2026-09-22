import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import '../../../../packages/ubaa_app/test/offline/startup_test.dart'
    as fixtures;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生接口只读枚举可用，脱敏宿主网络提示后原位恢复', (tester) async {
    // 只验证系统枚举可调用，不输出地址，不把接口存在当学校可达证据。
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );
    expect(interfaces, isA<List<NetworkInterface>>());
    final events = StreamController<void>.broadcast();
    final backend = fixtures.FakeRecoveryBackend()
      ..authError = const BackendException(UbaaErrorCode.networkError);
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: await fixtures.savedAccounts(),
        networkChanges: events.stream,
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    backend.authError = null;
    events.add(null);
    events.add(null);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(backend.loginCalls, 0);
    expect(backend.readCalls, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });
}
