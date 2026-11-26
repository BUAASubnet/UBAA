import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/write_harness.dart';
import '../support/navigation.dart';

void _registerQueryTests() {
  testWidgets('每日课程筛选点选未上课即提交派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.signin
              ? const <FeatureDetail>[FeatureDetail(title: '上课课程')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.signin);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(UiDestination.study.icon));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.signin);
    await openQueryPanel(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '未上课'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.signinPending);
  });

  testWidgets('每日课程已完成时禁用重复上课入口', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.signin
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '已完成上课课程',
                    presentation: SigninPresentation(
                      courseId: 'synthetic-done',
                      actionTarget: 'schedule-done',
                      classBeginTime: '08:00',
                      classEndTime: '09:00',
                      signStatus: 1,
                    ),
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '误导目标'),
                      FeatureField(label: '上课状态', value: '未上课'),
                    ],
                    actions: <FeatureAction>[
                      SigninPerformAction(
                        scheduleId: 'schedule-done',
                        eligibility: ActionEligibility.denied,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFetchSigninQr: (_, _) async {
            reads++;
            throw StateError('已签到课程不读取二维码');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(UiDestination.study.icon));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.signin);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '上课'), findsNothing);
    expect(find.text('已签到'), findsOneWidget);
    expect(reads, 0);
  });

  testWidgets(
    '每日课程目标缺失或状态未知时不开二维码',
    (tester) => withClock(Clock.fixed(DateTime.utc(2026, 11, 26)), () async {
      final snapshots = <FeatureId, FeatureSnapshot>{
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.success,
            summary: '已加载',
            details: feature == FeatureId.signin
                ? const <FeatureDetail>[
                    FeatureDetail(
                      title: '缺失签到目标',
                      presentation: SigninPresentation(
                        courseId: 'public-course',
                        classBeginTime: '08:00',
                        classEndTime: '09:00',
                        signStatus: 0,
                      ),
                      fields: <FeatureField>[
                        FeatureField(label: '课程 ID', value: 'legacy-target'),
                        FeatureField(label: '上课状态', value: '未上课'),
                      ],
                    ),
                    FeatureDetail(
                      title: '未知签到状态',
                      presentation: SigninPresentation(
                        courseId: 'unknown-course',
                        actionTarget: 'unknown-target',
                        classBeginTime: '08:00',
                        classEndTime: '09:00',
                      ),
                      actions: <FeatureAction>[
                        SigninPerformAction(
                          scheduleId: 'unknown-target',
                          eligibility: ActionEligibility.unknown,
                        ),
                      ],
                    ),
                  ]
                : const <FeatureDetail>[],
          ),
      };
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: coordinatedShell(
            user: const UserSummary(username: 'student'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onFetchSigninQr: (_, _) async {
              reads++;
              throw StateError('无可用签到目标');
            },
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(UiDestination.study.icon));
      await tester.pumpAndSettle();
      await openFeature(tester, FeatureId.signin);
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '上课'),
      );
      expect(button.onPressed, isNull);
      expect(reads, 0);
    }),
  );

  testWidgets('成绩筛选点选已出成绩即提交派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.grades
              ? const <FeatureDetail>[FeatureDetail(title: '成绩')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.grades);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    );
    await openFeature(tester, FeatureId.grades);
    await openQueryPanel(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '已出成绩'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.gradesScored);
  });

  testWidgets('评教筛选点选待评课程即提交派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[FeatureDetail(title: '评教')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.evaluation);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(UiDestination.study.icon));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.evaluation);
    await openQueryPanel(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '待评课程'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.evaluationPending);
  });
}

void main() {
  _registerQueryTests();
}
