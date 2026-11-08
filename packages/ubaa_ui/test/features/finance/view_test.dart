import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/finance/view.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

FinanceIncome income(
  String id, {
  String? project = '助学金',
  String? description = '国家助学金',
  int? amount = 100000,
  int? tax = 0,
  int? paid = 100000,
  String? rate,
  String? date = '2026-10-15',
  String? year = '2026',
  String? month = '10',
}) => FinanceIncome(
  id: id,
  project: project,
  description: description,
  amountCents: amount,
  taxCents: tax,
  paidCents: paid,
  taxRate: rate,
  recordedDate: date,
  year: year,
  month: month,
);

FinanceSnapshot snapshot(
  List<FinanceIncome> entries, {
  bool fromCache = false,
  String? saveError,
}) => FinanceSnapshot(
  entries: entries,
  total: entries.length,
  route: ConnectionMode.direct,
  fetchedAt: DateTime.utc(2026, 11, 8, 14, 30),
  fromCache: fromCache,
  savedForOffline: !fromCache && saveError == null,
  saveError: saveError,
);

class Service implements FinanceService {
  Future<FinanceSnapshot?> Function()? onCached;
  Future<FinanceSnapshot> Function()? onRefresh;
  int refreshes = 0;
  @override
  Future<FinanceSnapshot?> cached() => onCached?.call() ?? Future.value(null);
  @override
  Future<FinanceSnapshot> refresh() {
    refreshes++;
    return onRefresh?.call() ?? Future.value(snapshot(const []));
  }
}

Future<void> pump(WidgetTester tester, FinanceService? service) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: FinanceView(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('金额按整数分显示千分位，缺失与零值分开', () {
    expect(financeYuan(123456789), '¥1,234,567.89');
    expect(financeYuan(5), '¥0.05');
    expect(financeYuan(0), '¥0.00');
    expect(financeYuan(-120000), '-¥1,200.00');
    expect(financeYuan(null), '—');
  });

  testWidgets('先显示离线记录再替换为在线结果，按月分组并合计当年实发', (tester) async {
    final online = Completer<FinanceSnapshot>();
    final service = Service()
      ..onCached = (() async => snapshot([income('old')], fromCache: true))
      ..onRefresh = () => online.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: FinanceView(service: service)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('国家助学金'), findsOneWidget);
    expect(find.textContaining('离线记录'), findsOneWidget);

    online.complete(
      snapshot([
        income(
          'a',
          project: '劳务费',
          description: '助教酬金',
          paid: 80000,
          amount: 100000,
          tax: 20000,
          date: '2026-10-20',
        ),
        income('b', date: '2026-09-15', month: '09'),
        income(
          'c',
          paid: 50000,
          amount: 50000,
          date: '2025-12-15',
          year: '2025',
          month: '12',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('离线记录'), findsNothing);
    expect(find.text('2026年实发合计'), findsOneWidget);
    expect(find.text('¥1,800.00'), findsOneWidget);
    expect(find.text('10月'), findsOneWidget);
    expect(find.text('9月'), findsOneWidget);
    // 默认显示最近一年，其他年份通过年份选项查看。
    expect(find.text('12月'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '2025年'));
    await tester.pumpAndSettle();
    expect(find.text('2025年实发合计'), findsOneWidget);
    expect(find.text('12月'), findsOneWidget);
    expect(find.text('10月'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部实发合计'), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2025年12月'), findsOneWidget);
  });

  testWidgets('搜索按项目和摘要筛选，合计跟随结果', (tester) async {
    final service = Service()
      ..onRefresh = () async => snapshot([
        income('a', project: '劳务费', description: '助教酬金', paid: 80000),
        income('b'),
      ]);
    await pump(tester, service);
    await tester.enterText(find.byType(TextField), '助教');
    await tester.pumpAndSettle();
    expect(find.text('助教酬金'), findsOneWidget);
    expect(find.text('国家助学金'), findsNothing);
    expect(find.text('搜索结果实发合计'), findsOneWidget);
    expect(find.text('¥800.00'), findsWidgets);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的记录'), findsOneWidget);
  });

  testWidgets('详情区分零税额与缺失税率并说明不代表到账', (tester) async {
    final service = Service()
      ..onRefresh = () async => snapshot([income('LS001')]);
    await pump(tester, service);
    await tester.tap(find.text('国家助学金'));
    await tester.pumpAndSettle();
    expect(find.text('应发金额'), findsOneWidget);
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('税率'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('2026年10月15日'), findsOneWidget);
    expect(find.text('LS001'), findsOneWidget);
    expect(find.textContaining('到账以银行为准'), findsWidgets);
  });

  testWidgets('首次读取失败显示错误并可重试', (tester) async {
    var fail = true;
    final service = Service()
      ..onRefresh = () async {
        if (fail) {
          throw const UiError(
            code: UbaaErrorCode.networkError,
            title: '网络不可用',
            message: '无法连接财务系统',
          );
        }
        return snapshot([income('a')]);
      };
    await pump(tester, service);
    expect(find.text('无法连接财务系统'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('国家助学金'), findsOneWidget);
    expect(find.text('无法连接财务系统'), findsNothing);
  });

  testWidgets('刷新失败保留上次记录并提示重试', (tester) async {
    final service = Service()
      ..onCached = (() async => snapshot([income('a')], fromCache: true))
      ..onRefresh = () async => throw StateError('offline');
    await pump(tester, service);
    expect(find.text('国家助学金'), findsOneWidget);
    expect(find.textContaining('刷新失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('空结果与存储空间不足分别提示', (tester) async {
    final service = Service()
      ..onRefresh = () async => snapshot(const [], saveError: 'capacity');
    await pump(tester, service);
    expect(find.text('暂无收入记录'), findsOneWidget);
    expect(find.textContaining('存储空间不足'), findsOneWidget);
  });

  testWidgets('刷新保留已显示记录且进行中不重复读取', (tester) async {
    var online = Completer<FinanceSnapshot>()
      ..complete(snapshot([income('a')]));
    final service = Service()..onRefresh = () => online.future;
    await pump(tester, service);
    online = Completer<FinanceSnapshot>();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await tester.tap(find.byTooltip('刷新'), warnIfMissed: false);
    await tester.pump();
    expect(service.refreshes, 2);
    expect(find.text('国家助学金'), findsOneWidget);
    online.complete(snapshot([income('b', description: '刷新后的记录')]));
    await tester.pumpAndSettle();
    expect(find.text('刷新后的记录'), findsOneWidget);
  });

  testWidgets('切换账号后丢弃旧服务迟到的结果', (tester) async {
    final late = Completer<FinanceSnapshot>();
    final first = Service()..onRefresh = () => late.future;
    final second = Service()
      ..onRefresh = () async => snapshot([income('n', description: '新账号记录')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinanceView(service: first)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinanceView(service: second)),
      ),
    );
    await tester.pumpAndSettle();
    late.complete(snapshot([income('o', description: '旧账号记录')]));
    await tester.pumpAndSettle();
    expect(find.text('新账号记录'), findsOneWidget);
    expect(find.text('旧账号记录'), findsNothing);
  });

  testWidgets('不支持财务的后端显示说明', (tester) async {
    await pump(tester, null);
    expect(find.text('此版本暂不支持财务查询'), findsOneWidget);
  });

  Widget shell(FinanceService? service) => MaterialApp(
    theme: UbaaTheme.light(),
    home: UbaaMainShell(
      user: const UserSummary(username: 'synthetic'),
      initialDestination: UiDestination.campus,
      financeService: service,
      snapshots: {
        for (final id in FeatureId.values)
          id: FeatureSnapshot(feature: id, status: FeatureLoadStatus.empty),
      },
      routePolicy: RoutePolicy.direct,
      telemetryEnabled: false,
      activeRoutes: const [ConnectionMode.direct],
      onRefresh: () async {},
      onRetryFeature: (_) async {},
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
      onTelemetryChanged: (_) {},
    ),
  );

  testWidgets('校园页入口打开财务查询并可返回', (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = Service()..onRefresh = () async => snapshot([income('a')]);
    await tester.pumpWidget(shell(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务查询'));
    await tester.pumpAndSettle();
    expect(find.text('国家助学金'), findsOneWidget);
    expect(service.refreshes, 1);
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.text('国家助学金'), findsNothing);
    expect(find.text('财务查询'), findsOneWidget);
  });

  testWidgets('后端不提供财务服务时校园页不显示入口', (tester) async {
    await tester.pumpWidget(shell(null));
    await tester.pumpAndSettle();
    expect(find.text('iHome'), findsOneWidget);
    expect(find.text('财务查询'), findsNothing);
  });
}
