import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/recovery.dart' as startup;
import 'package:ubaa_test_support/privacy.dart';

void main() {
  testWidgets('退出后返回前台不取组件暂存链接', (tester) async {
    var takes = 0;
    _mockTake(tester, () async {
      takes++;
      return null;
    });
    final (accounts, _) = await _mountLaunchHost(tester);
    expect(takes, 1);
    await _logout(tester, accounts);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(takes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(takes, 1);
  });
  testWidgets('取组件链接异常只丢弃本次，返回前台仍可再取', (tester) async {
    var takes = 0;
    _mockTake(tester, () async {
      if (++takes == 1) throw PlatformException(code: 'synthetic');
      return null;
    });
    await _mountLaunchHost(tester);
    expect(takes, 1);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(takes, 2);
  });
  testWidgets('同一宿主退出换号后，新首页首帧重新取组件链接', (tester) async {
    var takes = 0;
    _mockTake(tester, () async {
      takes++;
      return null;
    });
    final (accounts, _) = await _mountLaunchHost(tester);
    expect(takes, 1);
    await _logout(tester, accounts);
    await _login(tester, accounts, 'fixture-other');
    expect(takes, 2);
  });
  testWidgets('主界面未挂载时收到的组件链接，首帧只派发最新一条', (tester) async {
    _mockTake(tester, () async => null);
    final (accounts, owner) = await _mountLaunchHost(tester, signedIn: false);
    expect(find.byType(UbaaMainShell), findsNothing);
    for (final date in ['2050-02-20', '2050-03-21']) {
      final raw = Uri(
        scheme: 'ubaa',
        host: 'widget',
        path: '/open',
        queryParameters: {'owner': owner, 'target': 'agenda', 'date': date},
      );
      final reply = await tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            _launchChannel.name,
            _launchChannel.codec.encodeMethodCall(MethodCall('launch', '$raw')),
            null,
          );
      expect(_launchChannel.codec.decodeEnvelope(reply!), isNull);
    }
    await _login(tester, accounts, 'fixture-user');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      UiDestination.agenda.index,
    );
    expect(find.text('2050年3月').hitTestable(), findsOneWidget);
  });
  testWidgets('宿主从本地账号发布组件且退出立即撤销，不等待线上认证', (tester) async {
    final backend = _Backend()..gate = Completer<AuthStatus>();
    final gateway = _Gateway();
    final accounts = await startup.widgetAccounts(tester);
    final owner = (await tester.runAsync(accounts.read))!.account!.id;
    await tester.pumpWidget(
      UbaaAppHost(
        preferenceValues: acceptedPrivacyPreferences(),
        backend: backend,
        localAccountStore: accounts,
        scheduleWidgetGateway: gateway,
      ),
    );
    await accounts.settle(tester);
    expect(gateway.owners, contains(owner));
    await tester.pump(const Duration(milliseconds: 1500));
    await accounts.settle(tester);
    expect(gateway.published, [owner]);
    final begins = gateway.owners.length;
    await tester.pump();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final epoch = shell.agendaEpoch;
    final reads = backend.storage.widgetQueries.length;
    expect(reads, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await accounts.settle(tester);
    expect(backend.storage.widgetQueries.length, greaterThan(reads));
    final query = backend.storage.widgetQueries.last;
    expect(query.from, query.now.rfc3339.substring(0, 10));
    expect(query.now.rfc3339, endsWith('T00:00:00+08:00'));
    expect(query.includeHidden, false);
    expect(
      tester.widget<UbaaMainShell>(find.byType(UbaaMainShell)).agendaEpoch,
      epoch,
    );
    expect(gateway.owners, hasLength(begins));
    final logout = shell.onLogout();
    await tester.pump();
    expect(gateway.owners.last, isNull);
    backend.gate!.complete(AuthStatus.signedOut);
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    await logout;
    expect(gateway.published, [owner]);
    await tester.pumpWidget(const SizedBox());
  });
}

const _launchChannel = MethodChannel('cn.edu.buaa.ubaa/widget-launch');

void _mockTake(WidgetTester tester, Future<String?> Function() take) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_launchChannel, (call) {
    expect(call.method, 'take');
    return take();
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_launchChannel, null));
}

Future<(startup.WidgetAccounts, String)> _mountLaunchHost(
  WidgetTester tester, {
  bool signedIn = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final accounts = await startup.widgetAccounts(tester);
  final owner = (await tester.runAsync(accounts.read))!.account!.id;
  if (!signedIn) await tester.runAsync(accounts.signOut);
  await tester.pumpWidget(
    UbaaAppHost(
      preferenceValues: acceptedPrivacyPreferences(),
      backend: _Backend()..signedIn = signedIn,
      localAccountStore: accounts,
      widgetLaunchChannel: WidgetLaunchChannel(),
    ),
  );
  await accounts.settle(tester);
  await tester.pumpAndSettle();
  return (accounts, owner);
}

Future<void> _logout(
  WidgetTester tester,
  startup.WidgetAccounts accounts,
) async {
  final logout = tester
      .widget<UbaaMainShell>(find.byType(UbaaMainShell))
      .onLogout();
  await accounts.settle(tester);
  await logout;
  await tester.pumpAndSettle();
  expect(find.byType(UbaaLoginView), findsOneWidget);
}

Future<void> _login(
  WidgetTester tester,
  startup.WidgetAccounts accounts,
  String username,
) async {
  final view = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
  view.onUsernameChanged(username);
  view.onPasswordChanged('synthetic-password');
  view.onSubmit();
  await accounts.settle(tester);
  await tester.pumpAndSettle();
  expect(find.byType(UbaaMainShell), findsOneWidget);
}

class _Backend extends startup.FakeRecoveryBackend
    implements OfflineQueryBackend, AgendaProvider {
  final storage = _LocalAgenda();
  @override
  late final agenda = AgendaService(storage);
  int queries = 0;
  @override
  Future<void> login(LoginInput input) async {
    await super.login(input);
    username = input.username;
  }

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

class _LocalAgenda implements AgendaBackend {
  final widgetQueries = <AgendaQuery>[];
  @override
  Future<void> openAccount(String accountId) async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<AgendaQueryResult> query(AgendaQuery query) async {
    if (DateTime.parse(
          query.to,
        ).difference(DateTime.parse(query.from)).inDays ==
        28)
      widgetQueries.add(query);
    return AgendaQueryResult(entries: [], sources: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
