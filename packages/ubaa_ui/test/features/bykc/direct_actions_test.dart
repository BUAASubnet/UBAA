import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/navigation.dart';
import '../../support/write_harness.dart';

void main() {
  for (final chosen in [false, true]) {
    testWidgets('${chosen ? '已选' : '可选'}列表按钮直接提交一次且不触发卡片导航', (tester) async {
      final gate = Completer<WriteCommitResult>();
      final state = await mount(
        tester,
        chosen: chosen,
        commit: () => gate.future,
      );
      final label = chosen ? '退选' : '选课';
      final button = find.widgetWithText(OutlinedButton, label);
      final before = state.queries.length;
      await tester.tap(button);
      await tester.pump();
      if (chosen) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认退选'));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.targets, [(state.operation, 71)]);
      expect(state.commits, 1);
      expect(state.queries.length, before);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '${label}中…'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '${label}中…'));
      await tester.pump();
      expect(state.commits, 1);
      gate.complete(result(state.operation));
      await tester.pumpAndSettle();
      expect(state.readbacks, 1);
      expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
      expect(state.commits, 1);
    });
  }
  for (final unknown in [false, true]) {
    testWidgets('列表选课${unknown ? '结果未知' : '失败'}保留页面且不自动重试', (tester) async {
      final state = await mount(
        tester,
        commit: () async => result(
          WriteOperation.bykcSelectCourse,
          success: false,
          unknown: unknown,
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '选课'));
      await tester.pumpAndSettle();
      expect(state.commits, 1);
      expect(state.readbacks, unknown ? 1 : 0);
      expect(find.widgetWithText(AppBar, FeatureId.bykc.title), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(state.commits, 1);
    });
  }
  testWidgets('列表未知资格禁止选课，点击正文仍能打开详情', (tester) async {
    final state = await mount(
      tester,
      allowed: false,
      commit: () async => result(WriteOperation.bykcSelectCourse),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选课'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('合成课程'));
    await tester.pumpAndSettle();
    expect(state.queries.last.view, FeatureQueryView.bykcDetail);
    expect(state.targets, isEmpty);
    expect(state.commits, 0);
  });
}

WriteCommitResult result(
  WriteOperation operation, {
  bool success = true,
  bool unknown = false,
}) => WriteCommitResult(
  operation: operation,
  success: success,
  outcomeUnknown: unknown,
  message: success ? '操作成功' : '操作未完成',
  resolvedRoute: ConnectionMode.direct,
);

class Scenario {
  Scenario(this.chosen, this.allowed);
  final bool chosen, allowed;
  int commits = 0, readbacks = 0, revision = 1;
  final targets = <(WriteOperation, int)>[];
  final queries = <FeatureQuery>[];
  late StateSetter update;
  late FeatureSnapshot snapshot;
  WriteOperation get operation => chosen
      ? WriteOperation.bykcDeselectCourse
      : WriteOperation.bykcSelectCourse;
  FeatureSnapshot make(FeatureQuery query) => FeatureSnapshot(
    feature: FeatureId.bykc,
    status: FeatureLoadStatus.success,
    resolvedRoute: ConnectionMode.direct,
    updatedAt: DateTime(2026, 10, 26),
    readContext: FeatureReadContext(query: query, requestRevision: revision),
    details: [
      FeatureDetail(
        title: '合成课程',
        presentation: chosen
            ? const BykcChosenPresentation(
                recordId: 9001,
                courseId: 71,
                courseName: '合成课程',
              )
            : BykcCoursePresentation(
                id: 71,
                courseName: '合成课程',
                status: BykcCourseStatus.available,
                selected: false,
                isDetail: query.view == FeatureQueryView.bykcDetail,
              ),
        actions: [
          chosen
              ? BykcDeselectAction(
                  courseId: 71,
                  eligibility: allowed
                      ? ActionEligibility.allowed
                      : ActionEligibility.unknown,
                )
              : BykcSelectAction(
                  courseId: 71,
                  eligibility: allowed
                      ? ActionEligibility.allowed
                      : ActionEligibility.unknown,
                ),
        ],
        readNavigation: const FeatureReadNavigation(
          feature: FeatureId.bykc,
          query: FeatureQuery(
            view: FeatureQueryView.bykcDetail,
            courseId: '71',
          ),
        ),
      ),
    ],
  );
}

Future<Scenario> mount(
  WidgetTester tester, {
  bool chosen = false,
  bool allowed = true,
  required Future<WriteCommitResult> Function() commit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final state = Scenario(chosen, allowed);
  state.snapshot = state.make(const FeatureQuery());
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, update) {
          state.update = update;
          return coordinatedShell(
            user: const UserSummary(username: 'synthetic'),
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            snapshots: {
              for (final feature in FeatureId.values)
                feature: feature == FeatureId.bykc
                    ? state.snapshot
                    : FeatureSnapshot(feature: feature),
            },
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onFeatureQuery: (_, query) async {
              state.queries.add(query);
              state.revision++;
              update(() => state.snapshot = state.make(query));
            },
            onPrepareBykcWrite: (operation, id) async {
              state.targets.add((operation, id));
              return WriteIntent(
                intentId: 'synthetic-intent',
                operation: operation,
                targetSummary: '合成课程',
                resolvedRoute: ConnectionMode.direct,
                warnings: const [],
                expiresAt: DateTime.now().add(const Duration(minutes: 2)),
                requestDigest: 'synthetic',
              );
            },
            onCommitWrite: (_) {
              state.commits++;
              return commit();
            },
            onWriteSuccess: (_, __) async {
              state.readbacks++;
            },
            onDiscardWriteIntent: (_) async {},
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
  await openFeature(tester, FeatureId.bykc);
  if (chosen) {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<FeatureQueryView>),
        matching: find.text('已选'),
      ),
    );
    await tester.pumpAndSettle();
  }
  return state;
}
