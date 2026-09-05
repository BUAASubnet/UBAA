part of '../widgets_test.dart';

void _registerSigninWriteResultTests() {
  testWidgets('课堂签到明确业务失败消费意图且不显示成功或刷新', (tester) async {
    var commitCalls = 0;
    var refreshCalls = 0;
    await _pumpSigninResult(
      tester,
      onCommit: () {
        commitCalls++;
        return const WriteCommitResult(
          operation: WriteOperation.signinPerform,
          success: false,
          message: '签到未完成',
          outcomeUnknown: false,
        );
      },
      onRefresh: () => refreshCalls++,
    );

    expect(commitCalls, 1);
    expect(refreshCalls, 0);
    expect(find.text('签到未完成'), findsOneWidget);
    expect(find.text('课堂签到已提交'), findsNothing);
    expect(find.text('确认课堂签到'), findsNothing);
  });

  testWidgets('课堂签到结果未知消费意图并刷新一次且只显示固定提示', (tester) async {
    var commitCalls = 0;
    var refreshCalls = 0;
    await _pumpSigninResult(
      tester,
      onCommit: () {
        commitCalls++;
        return const WriteCommitResult(
          operation: WriteOperation.signinPerform,
          success: false,
          message: '不可信响应 token=secret-safe@example.test',
          outcomeUnknown: true,
        );
      },
      onRefresh: () => refreshCalls++,
    );

    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.textContaining('secret-safe@example.test'), findsNothing);
    expect(find.text('确认课堂签到'), findsNothing);
  });
}

Future<void> _pumpSigninResult(
  WidgetTester tester, {
  required WriteCommitResult Function() onCommit,
  required void Function() onRefresh,
}) async {
  final snapshots = <FeatureId, FeatureSnapshot>{
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        summary: '已加载',
        details: feature == FeatureId.signin
            ? const <FeatureDetail>[
                FeatureDetail(
                  title: '课堂签到课程',
                  actions: <FeatureAction>[
                    SigninPerformAction(
                      scheduleId: 'schedule-result-safe',
                      eligibility: ActionEligibility.allowed,
                    ),
                  ],
                ),
              ]
            : const <FeatureDetail>[],
      ),
  };
  final intent = WriteIntent(
    intentId: 'signin-result-intent',
    operation: WriteOperation.signinPerform,
    targetSummary: '课堂签到课程',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
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
        onPrepareSigninWrite: (_) async => intent,
        onCommitWrite: (_) async => onCommit(),
        onWriteSuccess: (_, __) async => onRefresh(),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('课堂签到'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('准备签到'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认提交'));
  await tester.pumpAndSettle();
}
