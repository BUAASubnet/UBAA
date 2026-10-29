import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/write_harness.dart';
import '../support/navigation.dart';

void _registerInitialWriteTests() {
  testWidgets('博雅签到签退选课一点即完成，退选先弹窗确认', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '42'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.allowed,
                      ),
                      BykcDeselectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.allowed,
                      ),
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signOut,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: true,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var deselectCalls = 0;
    var signCalls = 0;
    final signTypes = <int>[];
    var commitCalls = 0;
    var refreshCalls = 0;
    final discardedIntentIds = <String>[];
    String? committedIntent;
    final intent = WriteIntent(
      intentId: 'intent-42',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '选择课程 42',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['提交后请刷新已选课程确认结果'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
    final signIntent = WriteIntent(
      intentId: 'sign-intent-42',
      operation: WriteOperation.bykcSignCourse,
      targetSummary: '博雅课程 42 签到',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['位置或时间窗要求由 Core 校验'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'sign-digest',
    );
    final deselectIntent = WriteIntent(
      intentId: 'deselect-intent-42',
      operation: WriteOperation.bykcDeselectCourse,
      targetSummary: '退选课程 42',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['请确认退选课程和截止时间'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'deselect-digest',
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
          onPrepareBykcWrite: (operation, courseId) async {
            expect(courseId, 42);
            if (operation == WriteOperation.bykcSelectCourse) {
              prepareCalls++;
              return intent;
            }
            expect(operation, WriteOperation.bykcDeselectCourse);
            deselectCalls++;
            return deselectIntent;
          },
          onPrepareBykcSignWrite: (action) async {
            signCalls++;
            expect(action.courseId, 42);
            signTypes.add(action.signType);
            expect(action.signType, anyOf(1, 2));
            return signIntent;
          },
          onDiscardWriteIntent: (intentId) async {
            discardedIntentIds.add(intentId);
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            committedIntent = intentId;
            final operation = switch (intentId) {
              'deselect-intent-42' => WriteOperation.bykcDeselectCourse,
              'sign-intent-42' => WriteOperation.bykcSignCourse,
              _ => WriteOperation.bykcSelectCourse,
            };
            return WriteCommitResult(
              operation: operation,
              success: true,
              message: operation == WriteOperation.bykcDeselectCourse
                  ? '退选结果已提交，请刷新已选课程确认'
                  : '已提交，请刷新已选课程确认',
              outcomeUnknown: false,
              resolvedRoute: ConnectionMode.direct,
            );
          },
          onWriteSuccess: (operation, _) async {
            expect(
              operation,
              anyOf(
                WriteOperation.bykcSelectCourse,
                WriteOperation.bykcDeselectCourse,
                WriteOperation.bykcSignCourse,
              ),
            );
            refreshCalls++;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await openFeature(tester, FeatureId.bykc);
    await tester.pumpAndSettle();
    // 签到、签退与选课一点即完成；退选不可撤销，先弹窗确认。
    await tester.tap(find.text('博雅签到'));
    await tester.pumpAndSettle();
    expect(signCalls, 1);
    expect(signTypes, <int>[1]);
    expect(find.text('确认博雅签到'), findsNothing);
    expect(commitCalls, 1);
    expect(committedIntent, 'sign-intent-42');
    await tester.tap(find.text('博雅签退'));
    await tester.pumpAndSettle();
    expect(signCalls, 2);
    expect(signTypes, <int>[1, 2]);
    expect(commitCalls, 2);
    await tester.tap(find.text('选课'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(find.text('确认博雅选课'), findsNothing);
    expect(commitCalls, 3);
    expect(committedIntent, 'intent-42');

    await tester.tap(find.text('退选'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();
    expect(deselectCalls, 0);
    expect(commitCalls, 3);
    await tester.tap(find.text('退选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认退选'));
    await tester.pumpAndSettle();
    expect(deselectCalls, 1);
    expect(find.text('确认博雅退选'), findsNothing);
    expect(commitCalls, 4);
    expect(committedIntent, 'deselect-intent-42');
    expect(discardedIntentIds, isEmpty);
    expect(refreshCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('prepare 在主界面卸载后返回时 best-effort 释放晚到的 intent', (tester) async {
    final prepared = Completer<WriteIntent>();
    final discardedIntentIds = <String>[];
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    actions: <FeatureAction>[
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareBykcSignWrite: (_) => prepared.future,
          onDiscardWriteIntent: (intentId) async {
            discardedIntentIds.add(intentId);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await openFeature(tester, FeatureId.bykc);
    await tester.pumpAndSettle();
    await tester.tap(find.text('博雅签到'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    prepared.complete(
      WriteIntent(
        intentId: 'intent-after-unmount',
        operation: WriteOperation.bykcSignCourse,
        targetSummary: '课程签到',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
    );
    await tester.pumpAndSettle();

    expect(discardedIntentIds, <String>['intent-after-unmount']);
  });

  testWidgets('课堂签到从 typed 签到目标一点即提交', (tester) async {
    const expectedAction = SigninPerformAction(
      scheduleId: 'schedule-7',
      eligibility: ActionEligibility.allowed,
    );
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
                    presentation: SigninPresentation(
                      courseId: '展示课程编号',
                      classBeginTime: '08:00',
                      classEndTime: '09:40',
                      signStatus: 0,
                    ),
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '误导目标'),
                      FeatureField(label: '签到状态', value: '已签到'),
                    ],
                    actions: <FeatureAction>[expectedAction],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var commitCalls = 0;
    var refreshCalls = 0;
    final intent = WriteIntent(
      intentId: 'signin-intent',
      operation: WriteOperation.signinPerform,
      targetSummary: '课堂签到课程',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const <String>['提交后请刷新今日签到状态确认结果'],
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
          onPrepareSigninWrite: (action) async {
            prepareCalls++;
            expect(identical(action, expectedAction), isTrue);
            expect(action.scheduleId, 'schedule-7');
            expect(action.eligibility, ActionEligibility.allowed);
            return intent;
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'signin-intent');
            return const WriteCommitResult(
              operation: WriteOperation.signinPerform,
              success: true,
              message: '签到结果已提交，请刷新确认',
              outcomeUnknown: false,
            );
          },
          onWriteSuccess: (operation, _) async {
            expect(operation, WriteOperation.signinPerform);
            refreshCalls++;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(UiDestination.coursework.icon));
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.signin);
    await tester.pumpAndSettle();
    // 点击签到即准备并提交，不再出现确认页。
    await tester.tap(find.widgetWithText(FilledButton, '签到'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(find.text('确认课堂签到'), findsNothing);
    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(find.text('签到结果已提交，请刷新确认'), findsOneWidget);
  });
}

void _registerRemainingWriteTests() {
  testWidgets('写入确认显示实际路线并防止过期提交', (tester) async {
    final intent = WriteIntent(
      intentId: 'intent',
      operation: WriteOperation.libbookCancelBooking,
      targetSummary: '取消一条图书馆预约',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const <String>['取消操作可能不可恢复'],
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      requestDigest: 'digest',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: WriteConfirmationView(
          intent: intent,
          onCancel: () {},
          onConfirm: () async {},
        ),
      ),
    );
    expect(find.text('WebVPN'), findsOneWidget);
    expect(find.text('确认已过期'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认已过期'),
    );
    expect(submit.onPressed, isNull);
  });
}

void main() {
  _registerInitialWriteTests();
  _registerRemainingWriteTests();
}
