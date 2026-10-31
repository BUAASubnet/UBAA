import 'dart:async';
import 'package:clock/clock.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

class _FakeCampusService implements CampusAccountService {
  int calls = 0;
  bool failNetwork = false;
  CampusAccountSnapshot snapshot = const CampusAccountSnapshot();
  Completer<void>? gate;
  final _at = DateTime.utc(2026, 10, 30, 8);

  @override
  Future<CampusAccountSnapshot> cached() async => snapshot;

  @override
  Future<PortalIdentity> identity() async {
    calls++;
    await gate?.future;
    return PortalIdentity(identity: '本科生', department: '合成学院', fetchedAt: _at);
  }

  @override
  Future<CampusMetrics> metrics() async {
    await gate?.future;
    return _metrics();
  }

  CampusMetrics _metrics() => CampusMetrics(
    cardBalance: CampusMetricValue(
      const CampusAmount(value: '0', unit: '元'),
      fetchedAt: _at,
    ),
    networkBalance: CampusMetricFailure('暂不可用', fetchedAt: _at),
    unreadMail: CampusMetricValue(3, fetchedAt: _at),
    borrowedBooks: CampusMetricValue(0, fetchedAt: _at),
    cloudStorageRemaining: CampusMetricValue(
      const CampusAmount(value: '48.6', unit: 'G'),
      fetchedAt: _at,
    ),
  );

  @override
  Future<NetworkUsage> networkUsage() async {
    await gate?.future;
    if (failNetwork) {
      throw const UiError(
        code: UbaaErrorCode.upstreamUnavailable,
        title: '读取失败',
        message: '网费系统暂不可用',
      );
    }
    return NetworkUsage(
      fetchedAt: _at,
      products: const [
        NetworkProductUsage(
          productName: '合成网络产品',
          used: CampusAmount(value: '36.42', unit: 'G'),
          freeRemaining: CampusAmount(value: '13.58', unit: 'G'),
          billableRemaining: CampusAmount(value: '0', unit: 'G'),
        ),
      ],
    );
  }
}

Widget _app(
  CampusAccountService service, {
  String account = 'synthetic',
  Clock? now,
}) => MaterialApp(
  home: UbaaMainShell(
    user: UserSummary(username: account, displayName: '测试同学'),
    campusAccountService: service,
    homeClock: now,
    snapshots: {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(feature: feature),
    },
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  ),
);

Future<void> _openMe(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tab-我的')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('五分钟内复用，过期后再次进入后台刷新并保留旧值', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime.utc(2026, 10, 31);
    final service = _FakeCampusService();
    await tester.pumpWidget(_app(service, now: Clock(() => now)));
    await tester.pumpAndSettle();
    await _openMe(tester);
    now = now.add(const Duration(minutes: 4));
    await tester.tap(find.byKey(const ValueKey('tab-首页')));
    await tester.pumpAndSettle();
    await _openMe(tester);
    expect(service.calls, 1);
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('tab-首页')));
    await tester.pumpAndSettle();
    service.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('tab-我的')));
    await tester.pump();
    expect(service.calls, 2);
    expect(find.text('本科生'), findsOneWidget);
    service.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('旧服务迟到结果不能覆盖新绑定，下拉期间标题栏抑制忙碌提示', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final old = _FakeCampusService()..gate = Completer<void>();
    await tester.pumpWidget(_app(old));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-我的')));
    await tester.pump();
    final current = _FakeCampusService();
    await tester.pumpWidget(_app(current));
    await tester.pumpAndSettle();
    expect(current.calls, 1);
    old.gate!.complete();
    await tester.pumpAndSettle();
    expect(current.calls, 1);
    current.gate = Completer<void>();
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(current.calls, 2);
    expect(find.byKey(const ValueKey('sync-busy')), findsNothing);
    current.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('账号变化即使复用同一服务也清除旧快照并重新读取', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeCampusService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    await _openMe(tester);
    service.gate = Completer<void>();
    await tester.pumpWidget(_app(service, account: 'second'));
    await tester.pump();
    expect(find.text('本科生'), findsNothing);
    expect(service.calls, 2);
    service.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('进入“我的”才读取，单项失败只影响对应格，切换标签不重复请求', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeCampusService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(service.calls, 0);

    await _openMe(tester);
    expect(service.calls, 1);
    expect(find.text('本科生'), findsWidgets);
    // 有效零值照常显示，失败项显示“获取失败”而不是零。
    final card = find.byKey(const ValueKey('me-metric-card'));
    expect(
      find.descendant(of: card, matching: find.textContaining('0')),
      findsOneWidget,
    );
    final fee = find.byKey(const ValueKey('me-metric-network-fee'));
    expect(
      find.descendant(of: fee, matching: find.text('获取失败')),
      findsOneWidget,
    );
    expect(find.text('合成网络产品'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-首页')));
    await tester.pumpAndSettle();
    await _openMe(tester);
    expect(service.calls, 1);
  });

  testWidgets('下拉刷新失败时保留旧流量并显示错误', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeCampusService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    await _openMe(tester);

    service.failNetwork = true;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.text('合成网络产品'), findsOneWidget);
    expect(find.text('网费系统暂不可用'), findsOneWidget);
  });

  testWidgets('先显示本机快照，在线结果到达后静默替换', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final at = DateTime.utc(2026, 10, 29, 8);
    final service = _FakeCampusService()
      ..gate = Completer<void>()
      ..snapshot = CampusAccountSnapshot(
        identity: PortalIdentity(
          identity: '缓存身份',
          department: '合成学院',
          fetchedAt: at,
        ),
        // 快照缺少的项为 null，不能显示成失败或零。
        metrics: CampusMetrics(
          networkBalance: CampusMetricValue(
            const CampusAmount(value: '10.66', unit: '元'),
            fetchedAt: at,
          ),
          cardBalance: null,
          unreadMail: null,
          borrowedBooks: null,
          cloudStorageRemaining: null,
        ),
      );
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-我的')));
    await tester.pump();
    await tester.pump();

    expect(find.text('缓存身份'), findsOneWidget);
    final fee = find.byKey(const ValueKey('me-metric-network-fee'));
    expect(
      find.descendant(
        of: fee,
        matching: find.textContaining('10.66', findRichText: true),
      ),
      findsOneWidget,
    );
    final card = find.byKey(const ValueKey('me-metric-card'));
    expect(
      find.descendant(of: card, matching: find.text('获取失败')),
      findsNothing,
    );

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('缓存身份'), findsNothing);
    expect(find.text('本科生'), findsOneWidget);
  });
}
