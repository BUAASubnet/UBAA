part of '../widgets_test.dart';

const _libbookResultAction = LibbookReserveAction(
  areaId: 'area-result-safe',
  seatId: 'seat-result-safe',
  day: '2026-09-04',
  segment: 'segment-result-safe',
  startTime: '08:00',
  endTime: '10:00',
  eligibility: ActionEligibility.allowed,
);

void _registerLibbookWriteResultTests() {
  testWidgets('图书馆预约 denied unknown 或 action 缺失时默认拒绝', (tester) async {
    var prepareCalls = 0;
    final snapshots = _libbookSnapshots(<FeatureDetail>[
      const FeatureDetail(
        title: '缺失 action 的座位',
        fields: <FeatureField>[
          FeatureField(label: '分区 ID', value: 'display-area-only'),
          FeatureField(label: '座位 ID', value: 'display-seat-only'),
          FeatureField(label: '日期', value: '2026-09-04'),
          FeatureField(label: '时段', value: '3'),
          FeatureField(label: '开始时间', value: '08:00'),
          FeatureField(label: '结束时间', value: '10:00'),
          FeatureField(label: '可预约', value: '是'),
        ],
      ),
      const FeatureDetail(
        title: 'denied 座位',
        fields: <FeatureField>[FeatureField(label: '可预约', value: '是')],
        actions: <FeatureAction>[
          LibbookReserveAction(
            areaId: 'area-denied',
            seatId: 'seat-denied',
            day: '2026-09-04',
            segment: '3',
            startTime: '08:00',
            endTime: '10:00',
            eligibility: ActionEligibility.denied,
          ),
        ],
      ),
      const FeatureDetail(
        title: 'unknown 座位',
        fields: <FeatureField>[FeatureField(label: '可预约', value: '是')],
        actions: <FeatureAction>[
          LibbookReserveAction(
            areaId: 'area-unknown',
            seatId: 'seat-unknown',
            day: '2026-09-04',
            segment: '3',
            startTime: '08:00',
            endTime: '10:00',
            eligibility: ActionEligibility.unknown,
          ),
        ],
      ),
    ]);

    await _pumpLibbookShell(
      tester,
      snapshots: snapshots,
      onPrepare: (_) async {
        prepareCalls++;
        throw StateError('不应调用图书馆预约 prepare');
      },
    );

    final missingButton = _libbookButtonFor('缺失 action 的座位');
    final deniedButton = _libbookButtonFor('denied 座位');
    final unknownButton = _libbookButtonFor('unknown 座位');
    expect(missingButton, findsNothing);
    expect(deniedButton, findsOneWidget);
    expect(unknownButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(deniedButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(unknownButton).onPressed, isNull);
    expect(prepareCalls, 0);
  });

  testWidgets('图书馆预约明确业务失败消费意图且最终提交只调用一次', (tester) async {
    var prepareCalls = 0;
    var commitCalls = 0;
    var refreshCalls = 0;
    final commit = Completer<WriteCommitResult>();
    await _pumpLibbookResult(
      tester,
      onPrepare: (action) {
        prepareCalls++;
        expect(identical(action, _libbookResultAction), isTrue);
      },
      onCommit: () {
        commitCalls++;
        return commit.future;
      },
      onRefresh: () => refreshCalls++,
    );

    expect(prepareCalls, 1);
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    expect(commitCalls, 1);
    commit.complete(
      const WriteCommitResult(
        operation: WriteOperation.libbookReserve,
        success: false,
        message: '预约未完成',
        outcomeUnknown: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(commitCalls, 1);
    expect(refreshCalls, 0);
    expect(find.text('预约未完成'), findsOneWidget);
    expect(find.text('图书馆预约已提交'), findsNothing);
    expect(find.text('确认图书馆预约'), findsNothing);
  });

  testWidgets('图书馆预约结果未知消费意图并刷新一次且隐藏不可信消息', (tester) async {
    var commitCalls = 0;
    var refreshCalls = 0;
    await _pumpLibbookResult(
      tester,
      onPrepare: (_) {},
      onCommit: () async {
        commitCalls++;
        return const WriteCommitResult(
          operation: WriteOperation.libbookReserve,
          success: false,
          message: '不可信响应 token=secret-safe@example.test',
          outcomeUnknown: true,
        );
      },
      onRefresh: () => refreshCalls++,
    );

    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.textContaining('secret-safe@example.test'), findsNothing);
    expect(find.text('确认图书馆预约'), findsNothing);
  });
}

const _libbookCancelAction = LibbookCancelAction(
  bookingId: 'booking-authority',
  page: 2,
  limit: 10,
  eligibility: ActionEligibility.allowed,
);

void _registerLibbookCancellationWriteTest() {
  testWidgets('图书馆取消只消费 typed action 并按同页上下文核对一次', (tester) async {
    var prepareCalls = 0;
    var commitCalls = 0;
    var refreshCalls = 0;
    FeatureQuery? readbackQuery;
    final commit = Completer<WriteCommitResult>();
    await _pumpLibbookCancelShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '图书馆预约',
          fields: <FeatureField>[
            FeatureField(label: '预约 ID', value: 'display-id-wrong'),
            FeatureField(label: '状态码', value: '8'),
            FeatureField(label: '状态', value: '展示文案声称已结束'),
          ],
          actions: <FeatureAction>[_libbookCancelAction],
        ),
      ],
      onPrepare: (action) async {
        prepareCalls++;
        expect(identical(action, _libbookCancelAction), isTrue);
        return WriteIntent(
          intentId: 'cancel-booking-authority',
          operation: WriteOperation.libbookCancelBooking,
          targetSummary: '取消图书馆预约脱敏目标',
          resolvedRoute: ConnectionMode.direct,
          warnings: const <String>['取消后请刷新预约记录确认状态'],
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          requestDigest: 'digest',
          readbackQuery: const FeatureQuery(
            view: FeatureQueryView.libbookBookings,
            page: 2,
            size: 10,
          ),
        );
      },
      onCommit: (_) {
        commitCalls++;
        return commit.future;
      },
      onRefresh: (operation, query) async {
        refreshCalls++;
        expect(operation, WriteOperation.libbookCancelBooking);
        readbackQuery = query;
      },
    );

    await tester.tap(find.text('准备取消预约'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(find.text('确认取消图书馆预约'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    expect(commitCalls, 1);
    commit.complete(
      const WriteCommitResult(
        operation: WriteOperation.libbookCancelBooking,
        success: true,
        message: '预约取消已提交',
        outcomeUnknown: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(readbackQuery?.view, FeatureQueryView.libbookBookings);
    expect(readbackQuery?.page, 2);
    expect(readbackQuery?.size, 10);
  });

  testWidgets('图书馆取消 denied unknown 或 action 缺失时默认拒绝', (tester) async {
    var prepareCalls = 0;
    await _pumpLibbookCancelShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '缺失 action 的预约',
          fields: <FeatureField>[
            FeatureField(label: '预约 ID', value: 'display-only'),
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
        ),
        FeatureDetail(
          title: 'denied 预约',
          fields: <FeatureField>[
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
          actions: <FeatureAction>[
            LibbookCancelAction(
              bookingId: 'booking-denied',
              page: 1,
              limit: 20,
              eligibility: ActionEligibility.denied,
            ),
          ],
        ),
        FeatureDetail(
          title: 'unknown 预约',
          fields: <FeatureField>[
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
          actions: <FeatureAction>[
            LibbookCancelAction(
              bookingId: 'booking-unknown',
              page: 1,
              limit: 20,
              eligibility: ActionEligibility.unknown,
            ),
          ],
        ),
      ],
      onPrepare: (_) async {
        prepareCalls++;
        throw StateError('非 allowed action 不应调用 prepare');
      },
    );

    expect(_libbookCancelButtonFor('缺失 action 的预约'), findsNothing);
    final denied = _libbookCancelButtonFor('denied 预约');
    final unknown = _libbookCancelButtonFor('unknown 预约');
    expect(denied, findsOneWidget);
    expect(unknown, findsOneWidget);
    expect(tester.widget<OutlinedButton>(denied).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(unknown).onPressed, isNull);
    expect(prepareCalls, 0);
  });

  testWidgets('图书馆取消确定业务 false 不刷新也不显示成功', (tester) async {
    var refreshCalls = 0;
    await _pumpLibbookCancelShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '可取消预约',
          actions: <FeatureAction>[_libbookCancelAction],
        ),
      ],
      onPrepare: (_) async => WriteIntent(
        intentId: 'cancel-false',
        operation: WriteOperation.libbookCancelBooking,
        targetSummary: '取消预约',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
      onCommit: (_) async => const WriteCommitResult(
        operation: WriteOperation.libbookCancelBooking,
        success: false,
        message: '预约取消未完成',
        outcomeUnknown: false,
      ),
      onRefresh: (_, __) async => refreshCalls++,
    );

    await tester.tap(find.text('准备取消预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(refreshCalls, 0);
    expect(find.text('预约取消未完成'), findsOneWidget);
  });
}

Future<void> _pumpLibbookCancelShell(
  WidgetTester tester, {
  required List<FeatureDetail> details,
  required LibbookCancelPreparer onPrepare,
  Future<WriteCommitResult> Function(String intentId)? onCommit,
  WriteSuccessHandler? onRefresh,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: coordinatedShell(
        user: const UserSummary(username: 'student'),
        snapshots: _libbookSnapshots(details),
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onPrepareLibbookCancelWrite: onPrepare,
        onCommitWrite: onCommit,
        onWriteSuccess: onRefresh,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.apps_outlined));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('图书馆座位'));
  await tester.tap(find.text('图书馆座位'));
  await tester.pumpAndSettle();
}

Future<void> _pumpLibbookResult(
  WidgetTester tester, {
  required void Function(LibbookReserveAction action) onPrepare,
  required Future<WriteCommitResult> Function() onCommit,
  required void Function() onRefresh,
}) async {
  final intent = WriteIntent(
    intentId: 'libbook-result-intent',
    operation: WriteOperation.libbookReserve,
    targetSummary: '图书馆预约脱敏目标',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
  await _pumpLibbookShell(
    tester,
    snapshots: _libbookSnapshots(const <FeatureDetail>[
      FeatureDetail(
        title: '图书馆预约结果座位',
        fields: <FeatureField>[
          FeatureField(label: '分区 ID', value: 'display-area-wrong'),
          FeatureField(label: '座位 ID', value: 'display-seat-wrong'),
          FeatureField(label: '日期', value: '1900-01-01'),
          FeatureField(label: '时段', value: 'display-segment-wrong'),
          FeatureField(label: '可预约', value: '否'),
        ],
        actions: <FeatureAction>[_libbookResultAction],
      ),
    ]),
    onPrepare: (action) async {
      onPrepare(action);
      return intent;
    },
    onCommit: (_) => onCommit(),
    onRefresh: (_, __) async => onRefresh(),
  );
  await tester.tap(find.text('准备预约此座位'));
  await tester.pumpAndSettle();
  expect(find.text('确认图书馆预约'), findsNWidgets(2));
}

Future<void> _pumpLibbookShell(
  WidgetTester tester, {
  required Map<FeatureId, FeatureSnapshot> snapshots,
  required Future<WriteIntent> Function(LibbookReserveAction action) onPrepare,
  Future<WriteCommitResult> Function(String intentId)? onCommit,
  WriteSuccessHandler? onRefresh,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: coordinatedShell(
        user: const UserSummary(username: 'student'),
        snapshots: snapshots,
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onPrepareLibbookReserveWrite: onPrepare,
        onCommitWrite: onCommit,
        onWriteSuccess: onRefresh,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.apps_outlined));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('图书馆座位'));
  await tester.tap(find.text('图书馆座位'));
  await tester.pumpAndSettle();
}

Map<FeatureId, FeatureSnapshot> _libbookSnapshots(
  List<FeatureDetail> details,
) => <FeatureId, FeatureSnapshot>{
  for (final feature in FeatureId.values)
    feature: FeatureSnapshot(
      feature: feature,
      status: FeatureLoadStatus.success,
      summary: '已加载',
      details: feature == FeatureId.libbook ? details : const <FeatureDetail>[],
    ),
};

Finder _libbookButtonFor(String title) {
  final card = find.ancestor(of: find.text(title), matching: find.byType(Card));
  return find.descendant(
    of: card,
    matching: find.widgetWithText(OutlinedButton, '准备预约此座位'),
  );
}

Finder _libbookCancelButtonFor(String title) {
  final card = find.ancestor(of: find.text(title), matching: find.byType(Card));
  return find.descendant(
    of: card,
    matching: find.widgetWithText(OutlinedButton, '准备取消预约'),
  );
}
