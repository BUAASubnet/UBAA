import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/write_harness.dart';

void main() {
  testWidgets('首页一次点击直接签到，连点只提交一次，成功立即移除对应待办', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 10, 26, 15)), () async {
      final gate = Completer<WriteCommitResult>();
      final state = await mount(tester, commit: () => gate.future);
      final button = find.widgetWithText(FilledButton, '签到').first;
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.commits, 1);
      expect(state.targets, ['canonical-1']);
      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      await tester.tap(find.text('课程1'));
      await tester.pump();
      expect(state.commits, 1);
      gate.complete(result(true));
      await tester.pumpAndSettle();
      expect(find.text('课程1'), findsNothing);
      expect(find.text('课程2'), findsOneWidget);
      state.rebuild(() {});
      await tester.pumpAndSettle();
      expect(find.text('课程1'), findsNothing);
    });
  });
  for (final unknown in [false, true]) {
    testWidgets('签到${unknown ? '结果未知' : '失败'}保留待办且不自动重试', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 26, 15)), () async {
        final state = await mount(
          tester,
          commit: () async => result(false, unknown: unknown),
        );
        await tester.tap(find.widgetWithText(FilledButton, '签到').first);
        await tester.pumpAndSettle();
        expect(state.commits, 1);
        expect(find.text('课程1'), findsOneWidget);
        expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(state.commits, 1);
      });
    });
  }
  testWidgets('缓存签到卡点击只刷新状态，不进入详情或直接提交', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 10, 26, 15)), () async {
      final state = await mount(
        tester,
        stale: true,
        commit: () async => result(true),
      );
      await tester.tap(find.text('课程1'));
      await tester.pumpAndSettle();
      expect(state.refreshes, 1);
      expect(state.targets, isEmpty);
      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '签到').first);
      await tester.pumpAndSettle();
      expect(state.commits, 1);
      expect(find.text('课程1'), findsNothing);
    });
  });
}

WriteCommitResult result(bool success, {bool unknown = false}) =>
    WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: success,
      message: success ? '签到成功' : '签到未完成',
      outcomeUnknown: unknown,
    );

class Scenario {
  int commits = 0, refreshes = 0;
  final targets = <String>[];
  late StateSetter rebuild;
}

Future<Scenario> mount(
  WidgetTester tester, {
  required Future<WriteCommitResult> Function() commit,
  bool stale = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final state = Scenario();
  final snapshots = {
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.empty,
      ),
  };
  snapshots[FeatureId.signin] = FeatureSnapshot(
    feature: FeatureId.signin,
    status: stale ? FeatureLoadStatus.stale : FeatureLoadStatus.success,
    details: [
      for (var i = 1; i <= 2; i++)
        FeatureDetail(
          title: '课程$i',
          presentation: SigninPresentation(
            courseId: 'display-$i',
            classBeginTime: '14:00',
            classEndTime: '17:00',
            signStatus: 0,
          ),
          actions: [
            SigninPerformAction(
              scheduleId: 'canonical-$i',
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (_, rebuild) {
          state.rebuild = rebuild;
          return coordinatedShell(
            user: const UserSummary(username: 'synthetic'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (id) async {
              state.refreshes++;
              rebuild(
                () => snapshots[id] = snapshots[id]!.copyWith(
                  status: FeatureLoadStatus.success,
                ),
              );
            },
            onFeatureQuery: (_, _) async {},
            onPrepareSigninWrite: (action) async {
              state.targets.add(action.scheduleId);
              return WriteIntent(
                intentId: 'synthetic-intent',
                operation: WriteOperation.signinPerform,
                targetSummary: '合成课程',
                resolvedRoute: ConnectionMode.direct,
                warnings: const [],
                expiresAt: DateTime.now().add(const Duration(minutes: 5)),
                requestDigest: 'synthetic-digest',
              );
            },
            onCommitWrite: (_) {
              state.commits++;
              return commit();
            },
            onWriteSuccess: (_, _) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}
