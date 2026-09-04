part of '../widgets_test.dart';

void _registerCgyyCancellationWriteTest() {
  testWidgets('场馆取消只消费 typed Allowed action 并双回读同 ID 核对', (tester) async {
    const action = CgyyCancelAction(
      orderId: 17,
      orderStatus: 1,
      checkStatus: 2,
      targetOrderId: 17,
      eligibility: ActionEligibility.allowed,
    );
    var prepareCalls = 0;
    var commitCalls = 0;
    var ordinaryRefreshCalls = 0;
    var verifyCalls = 0;
    await _pumpCgyyCancellationShell(
      tester,
      action: action,
      fields: const <FeatureField>[
        FeatureField(label: '订单编号', value: '999'),
        FeatureField(label: '订单状态', value: '2'),
        FeatureField(label: '审核状态', value: '-2'),
        FeatureField(label: '开始', value: '2000-01-01 00:00:00'),
      ],
      onPrepare: (received) async {
        prepareCalls++;
        expect(received, same(action));
        return WriteIntent(
          intentId: 'cancel-17',
          operation: WriteOperation.cgyyCancelOrder,
          targetSummary: '取消场馆订单 17',
          resolvedRoute: ConnectionMode.direct,
          warnings: const <String>['取消后将只读核对订单列表与详情'],
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          requestDigest: 'digest',
          readbackQuery: const FeatureQuery(
            view: FeatureQueryView.cgyyOrderDetail,
            orderId: 17,
          ),
        );
      },
      onCommit: (intentId) async {
        commitCalls++;
        expect(intentId, 'cancel-17');
        return const WriteCommitResult(
          operation: WriteOperation.cgyyCancelOrder,
          success: true,
          message: '场馆订单取消已提交',
          outcomeUnknown: false,
        );
      },
      onOrdinaryRefresh: (_, __) async => ordinaryRefreshCalls++,
      onVerify: ({required orderId, required expectedRoute}) async {
        verifyCalls++;
        expect(orderId, 17);
        expect(expectedRoute, ConnectionMode.direct);
        return true;
      },
    );

    await _openCgyyCancellation(tester);
    await tester.tap(find.text('准备取消订单'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认取消场馆订单'), findsNWidgets(2));

    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(verifyCalls, 1);
    expect(ordinaryRefreshCalls, 0);
    expect(find.text('场馆订单取消已提交（取消状态已核对）'), findsOneWidget);
  });

  testWidgets('场馆取消结果未知只双回读一次并显示固定禁止重试提示', (tester) async {
    const action = CgyyCancelAction(
      orderId: 17,
      orderStatus: 1,
      checkStatus: 2,
      targetOrderId: 17,
      eligibility: ActionEligibility.allowed,
    );
    var prepareCalls = 0;
    var commitCalls = 0;
    var verifyCalls = 0;
    await _pumpCgyyCancellationShell(
      tester,
      action: action,
      onPrepare: (_) async {
        prepareCalls++;
        return WriteIntent(
          intentId: 'cancel-unknown-17',
          operation: WriteOperation.cgyyCancelOrder,
          targetSummary: '取消场馆订单 17',
          resolvedRoute: ConnectionMode.direct,
          warnings: const <String>['请确认取消影响'],
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          requestDigest: 'digest',
          readbackQuery: const FeatureQuery(
            view: FeatureQueryView.cgyyOrderDetail,
            orderId: 17,
          ),
        );
      },
      onCommit: (_) async {
        commitCalls++;
        throw const UiError(
          code: UbaaErrorCode.outcomeUnknown,
          title: '提交结果未知',
          message: '不应透传的可变文案',
          retryable: false,
        );
      },
      onVerify: ({required orderId, required expectedRoute}) async {
        verifyCalls++;
        expect(orderId, 17);
        expect(expectedRoute, ConnectionMode.direct);
        return false;
      },
    );

    await _openCgyyCancellation(tester);
    await tester.tap(find.text('准备取消订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(prepareCalls, 1);
    expect(commitCalls, 1);
    expect(verifyCalls, 1);
    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
  });

  testWidgets('场馆取消 OutcomeUnknown 结果双回读成功时仅显示固定提示', (tester) async {
    const action = CgyyCancelAction(
      orderId: 17,
      orderStatus: 1,
      checkStatus: 2,
      targetOrderId: 17,
      eligibility: ActionEligibility.allowed,
    );
    var verifyCalls = 0;
    var ordinaryRefreshCalls = 0;
    await _pumpCgyyCancellationShell(
      tester,
      action: action,
      onPrepare: (_) async => WriteIntent(
        intentId: 'cancel-unknown-result-17',
        operation: WriteOperation.cgyyCancelOrder,
        targetSummary: '取消场馆订单 17',
        resolvedRoute: ConnectionMode.webvpn,
        warnings: const <String>['请确认取消影响'],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
        readbackQuery: const FeatureQuery(
          view: FeatureQueryView.cgyyOrderDetail,
          orderId: 17,
        ),
      ),
      onCommit: (_) async => const WriteCommitResult(
        operation: WriteOperation.cgyyCancelOrder,
        success: false,
        message: '不应展示的可变响应 token=secret',
        outcomeUnknown: true,
      ),
      onOrdinaryRefresh: (_, __) async => ordinaryRefreshCalls++,
      onVerify: ({required orderId, required expectedRoute}) async {
        verifyCalls++;
        expect(orderId, 17);
        expect(expectedRoute, ConnectionMode.webvpn);
        return true;
      },
    );

    await _openCgyyCancellation(tester);
    await tester.tap(find.text('准备取消订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(verifyCalls, 1);
    expect(ordinaryRefreshCalls, 0);
    expect(find.text('提交响应不确定，但场馆订单取消状态已核对，请勿重复提交。'), findsOneWidget);
    expect(find.textContaining('token=secret'), findsNothing);
  });

  testWidgets('场馆取消 denied unknown 或目标不一致时不显示取消入口', (tester) async {
    for (final action in const <CgyyCancelAction>[
      CgyyCancelAction(
        orderId: 17,
        orderStatus: 2,
        checkStatus: 2,
        targetOrderId: null,
        eligibility: ActionEligibility.denied,
      ),
      CgyyCancelAction(
        orderId: 17,
        orderStatus: null,
        checkStatus: null,
        targetOrderId: null,
        eligibility: ActionEligibility.unknown,
      ),
      CgyyCancelAction(
        orderId: 17,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 18,
        eligibility: ActionEligibility.allowed,
      ),
    ]) {
      await _pumpCgyyCancellationShell(tester, action: action);
      await _openCgyyCancellation(tester);
      expect(find.text('准备取消订单'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pumpCgyyCancellationShell(
  WidgetTester tester, {
  required CgyyCancelAction action,
  List<FeatureField> fields = const <FeatureField>[],
  CgyyCancelPreparer? onPrepare,
  Future<WriteCommitResult> Function(String intentId)? onCommit,
  WriteSuccessHandler? onOrdinaryRefresh,
  CgyyCancellationVerifier? onVerify,
}) => tester.pumpWidget(
  MaterialApp(
    theme: UbaaTheme.light(),
    home: UbaaMainShell(
      user: const UserSummary(username: 'student'),
      snapshots: <FeatureId, FeatureSnapshot>{
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.success,
            summary: '已加载',
            details: feature == FeatureId.cgyy
                ? <FeatureDetail>[
                    FeatureDetail(
                      title: '羽毛球馆订单',
                      fields: fields,
                      actions: <FeatureAction>[action],
                    ),
                  ]
                : const <FeatureDetail>[],
          ),
      },
      routePolicy: RoutePolicy.auto,
      telemetryEnabled: false,
      onRefresh: () async {},
      onRetryFeature: (_) async {},
      onPrepareCgyyCancelWrite: onPrepare,
      onCommitWrite: onCommit,
      onWriteSuccess: onOrdinaryRefresh,
      onVerifyCgyyCancellation: onVerify,
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
      onTelemetryChanged: (_) {},
    ),
  ),
);

Future<void> _openCgyyCancellation(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('场馆预约'));
  await tester.pumpAndSettle();
}
