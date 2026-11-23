import 'dart:async';
import 'package:clock/clock.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/app/account/campus_account_loader.dart';

class _FakeCampusService implements CampusAccountService {
  int calls = 0;
  bool failNetwork = false;
  CampusAccountSnapshot snapshot = const CampusAccountSnapshot();
  Completer<void>? gate;
  Completer<CampusAccountSnapshot>? cacheGate;
  final _at = DateTime.utc(2026, 10, 30, 8);

  @override
  Future<CampusAccountSnapshot> cached() async => cacheGate?.future ?? snapshot;

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
  RoutePolicy routePolicy = RoutePolicy.auto,
  Clock? now,
  LibraryLoansReader? readLibraryLoans,
  ValueChanged<String>? onFeatureOpened,
  LibraryLoanRenewPreparer? onPrepareLibraryLoanRenewWrite,
  WritePreparationRunner? onRunWritePrepare,
  WriteConfirmationRunner? onConfirmWrite,
  WriteCancellationRunner? onCancelWrite,
  WriteState writeState = const WriteState.idle(),
}) => MaterialApp(
  home: UbaaMainShell(
    user: UserSummary(username: account, displayName: '测试同学'),
    campusAccountService: service,
    homeClock: now,
    readLibraryLoans: readLibraryLoans,
    onFeatureOpened: onFeatureOpened,
    onPrepareLibraryLoanRenewWrite: onPrepareLibraryLoanRenewWrite,
    onRunWritePrepare: onRunWritePrepare,
    onConfirmWrite: onConfirmWrite,
    onCancelWrite: onCancelWrite,
    onDiscardWriteIntent: (_) async {},
    writeState: writeState,
    snapshots: {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(feature: feature),
    },
    routePolicy: routePolicy,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
  ),
);

Future<void> _openMe(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tab-我的')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点击待还图书打开当前借阅页面', (tester) async {
    final opened = <String>[];
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _FakeCampusService(),
        onFeatureOpened: opened.add,
        readLibraryLoans: () async => const [
          LibraryLoan(
            id: 'loan-1',
            title: '合成书目',
            author: '合成作者',
            loanDate: '2026-11-01',
            dueDate: '2026-12-01',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _openMe(tester);
    await tester.tap(find.byKey(const ValueKey('me-metric-books')));
    await tester.pumpAndSettle();
    expect(find.text('当前借阅'), findsOneWidget);
    expect(find.text('合成书目'), findsOneWidget);
    expect(find.text('共 1 本在借'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('me-metric-books')), findsOneWidget);
    expect(opened, ['library_loans']);
  });

  testWidgets('续借经既有确认流程提交并使用原路线核对结果', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var loans = const [
      LibraryLoan(
        id: 'loan-1',
        title: '合成书目',
        dueDate: '2026-12-01',
        renewTimes: 1,
        canRenewTimes: 1,
      ),
    ];
    var prepared = 0;
    var committed = 0;
    final intent = WriteIntent(
      intentId: 'intent-library',
      operation: WriteOperation.libraryLoanRenew,
      targetSummary: '《合成书目》',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
    await tester.pumpWidget(
      _app(
        _FakeCampusService(),
        readLibraryLoans: () async => loans,
        onPrepareLibraryLoanRenewWrite: (loanId) async {
          expect(loanId, 'loan-1');
          prepared++;
          return intent;
        },
        onRunWritePrepare: (prepare, {required expectedOperation}) async {
          expect(expectedOperation, WriteOperation.libraryLoanRenew);
          return prepare();
        },
        onConfirmWrite: () async {
          committed++;
          loans = const [
            LibraryLoan(
              id: 'loan-1',
              title: '合成书目',
              dueDate: '2027-01-05',
              renewTimes: 2,
              canRenewTimes: 0,
            ),
          ];
          return WriteOutcome(
            operation: WriteOperation.libraryLoanRenew,
            message: '续借成功',
            result: const WriteCommitResult(
              operation: WriteOperation.libraryLoanRenew,
              success: true,
              message: '续借成功',
              outcomeUnknown: false,
              resolvedRoute: ConnectionMode.direct,
            ),
            libraryLoanRenewReadback: LibraryLoanRenewReadback(
              loanId: 'loan-1',
              loans: loans,
              route: ConnectionMode.direct,
              status: LibraryRenewStatus.applied,
            ),
          );
        },
        onCancelWrite: () async {},
      ),
    );
    await tester.pumpAndSettle();
    await _openMe(tester);
    await tester.tap(find.byKey(const ValueKey('me-metric-books')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '续借'));
    await tester.pumpAndSettle();
    expect(find.text('续借这本书？'), findsOneWidget);
    expect(prepared, 0);
    await tester.tap(find.text('确认续借'));
    await tester.pumpAndSettle();
    expect(prepared, 1);
    expect(committed, 1);
    expect(find.text('续借 2 次'), findsOneWidget);
    expect(find.text('不可续借'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(RegExp(r'^续借成功，应还日期 (?:2027年)?1月5日$')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('待还图书每次续借被拒绝时显示本次学校原因', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const reasons = ['META-403060: 不允许续借,未达到到期前续借天数', '已有预约，无法续借'];
    var readCalls = 0;
    var committed = 0;
    await tester.pumpWidget(
      _app(
        _FakeCampusService(),
        readLibraryLoans: () async {
          readCalls++;
          return const [
            LibraryLoan(
              id: 'loan-1',
              title: '合成书目',
              dueDate: '2026-12-01',
              renewTimes: 1,
              canRenewTimes: 1,
            ),
          ];
        },
        onPrepareLibraryLoanRenewWrite: (_) async => WriteIntent(
          intentId: 'intent-library-rejected',
          operation: WriteOperation.libraryLoanRenew,
          targetSummary: '《合成书目》',
          resolvedRoute: ConnectionMode.direct,
          warnings: const <String>[],
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          requestDigest: 'digest',
        ),
        onRunWritePrepare: (prepare, {required expectedOperation}) async =>
            prepare(),
        onConfirmWrite: () async => WriteOutcome(
          operation: WriteOperation.libraryLoanRenew,
          message: reasons[committed++],
          error: const UiError(
            code: UbaaErrorCode.businessRejected,
            title: '操作未完成',
            message: '学校服务未接受本次操作',
          ),
        ),
        onCancelWrite: () async {},
      ),
    );
    await tester.pumpAndSettle();
    await _openMe(tester);
    await tester.tap(find.byKey(const ValueKey('me-metric-books')));
    await tester.pumpAndSettle();
    for (final (index, reason) in reasons.indexed) {
      await tester.tap(find.widgetWithText(FilledButton, '续借'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认续借'));
      await tester.pumpAndSettle();

      expect(find.text(reason), findsOneWidget);
      expect(find.text(reasons[1 - index]), findsNothing);
      expect(find.text('续借 1 次'), findsOneWidget);
      expect(committed, index + 1);
      expect(readCalls, 1);
    }
  });

  testWidgets('确认弹窗期间切换路线会丢弃旧续借操作', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var prepared = 0;
    var committed = 0;
    final intent = WriteIntent(
      intentId: 'intent-library-route',
      operation: WriteOperation.libraryLoanRenew,
      targetSummary: '《合成书目》',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
    Widget app(RoutePolicy policy) => _app(
      _FakeCampusService(),
      routePolicy: policy,
      readLibraryLoans: () async => const [
        LibraryLoan(
          id: 'loan-1',
          title: '合成书目',
          dueDate: '2026-12-01',
          renewTimes: 1,
          canRenewTimes: 1,
        ),
      ],
      onPrepareLibraryLoanRenewWrite: (_) async {
        prepared++;
        return intent;
      },
      onRunWritePrepare: (prepare, {required expectedOperation}) async {
        return prepare();
      },
      onConfirmWrite: () async {
        committed++;
        return const WriteOutcome(
          operation: WriteOperation.libraryLoanRenew,
          message: '续借成功',
          error: UiError(
            code: UbaaErrorCode.operationConflict,
            title: '已失效',
            message: '操作已失效',
          ),
        );
      },
      onCancelWrite: () async {},
    );
    await tester.pumpWidget(app(RoutePolicy.auto));
    await tester.pumpAndSettle();
    await _openMe(tester);
    await tester.tap(find.byKey(const ValueKey('me-metric-books')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '续借'));
    await tester.pumpAndSettle();
    expect(find.text('续借这本书？'), findsOneWidget);
    await tester.pumpWidget(app(RoutePolicy.webvpn));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认续借'));
    await tester.pumpAndSettle();
    expect(prepared, 0);
    expect(committed, 0);
  });

  test('缓存读取期间恢复在线会继续刷新校园账户', () async {
    final service = _FakeCampusService()..cacheGate = Completer();
    final loader = CampusAccountLoader(
      service: service,
      changed: () {},
      now: DateTime.now,
    );
    addTearDown(loader.dispose);
    loader.ensure(online: false);
    loader.ensure(online: true);
    expect(service.calls, 0);
    service.cacheGate!.complete(const CampusAccountSnapshot());
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, 1);
    expect(loader.overview!.identity.data?.department, '合成学院');
  });

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
      find.descendant(of: fee, matching: find.text('读取失败')),
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
      find.descendant(of: card, matching: find.text('读取失败')),
      findsNothing,
    );

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('缓存身份'), findsNothing);
    expect(find.text('本科生'), findsOneWidget);
  });
}
