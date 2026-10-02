import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../ubaa_app/test/offline/startup_test.dart' as startup;

void main() {
  testWidgets('宿主从本地账号发布组件且退出立即撤销，不等待线上认证', (tester) async {
    final backend = _Backend()..gate = Completer<AuthStatus>();
    final gateway = _Gateway();
    final accounts = await startup.savedAccounts();
    final owner = (await accounts.read())!.account!.id;
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: accounts,
        scheduleWidgetGateway: gateway,
      ),
    );
    for (var i = 0; i < 20 && gateway.published.isEmpty; i++) {
      await tester.pump();
    }
    expect(gateway.owners, contains(owner));
    expect(gateway.published, [owner]);
    expect(backend.queries, 1);
    await tester.pump();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final logout = shell.onLogout();
    await tester.pump();
    expect(gateway.owners.last, isNull);
    backend.gate!.complete(AuthStatus.signedOut);
    await tester.pumpAndSettle();
    await logout;
    expect(gateway.published, [owner]);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Backend extends startup.FakeRecoveryBackend
    implements OfflineQueryBackend {
  int queries = 0;
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    queries++;
    return const OfflineQueryRead(null);
  }
}

class _Gateway implements ScheduleWidgetGateway {
  final owners = <String?>[], published = <String>[];
  @override
  Future<String> begin(String? owner) async {
    owners.add(owner);
    return 'scope';
  }

  @override
  Future<void> publish(String scope, ScheduleWidgetSnapshot snapshot) async {
    published.add(snapshot.owner);
  }
}
