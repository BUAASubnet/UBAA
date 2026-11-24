import 'package:clock/clock.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';
import '../support/write_harness.dart';
import '../support/navigation.dart';

void _registerInitialWriteTests() {
  testWidgets('博雅上课下课选课一点即完成，退选先弹窗确认', (tester) async {
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
      targetSummary: '博雅课程 42 上课',
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
        ),
      ),
    );
    await openFeature(tester, FeatureId.bykc);
    await tester.pumpAndSettle();
    // 签到、签退与选课一点即完成；退选不可撤销，先弹窗确认。
    await tester.tap(find.text('博雅上课'));
    await tester.pumpAndSettle();
    expect(signCalls, 1);
    expect(signTypes, <int>[1]);
    expect(find.text('确认博雅上课'), findsNothing);
    expect(commitCalls, 1);
    expect(committedIntent, 'sign-intent-42');
    await tester.tap(find.text('博雅下课'));
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
    await tester.tap(find.text('取消'));
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
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareBykcSignWrite: (_) => prepared.future,
          onDiscardWriteIntent: (intentId) async {
            discardedIntentIds.add(intentId);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    );
    await openFeature(tester, FeatureId.bykc);
    await tester.pumpAndSettle();
    await tester.tap(find.text('博雅上课'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    prepared.complete(
      WriteIntent(
        intentId: 'intent-after-unmount',
        operation: WriteOperation.bykcSignCourse,
        targetSummary: '每日课程',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
    );
    await tester.pumpAndSettle();

    expect(discardedIntentIds, <String>['intent-after-unmount']);
  });

  testWidgets(
    '每日课程从 typed 上课目标一点即提交',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 29, 0, 10)), () async {
          const expectedAction = SigninPerformAction(
            scheduleId: 'schedule-7',
            eligibility: ActionEligibility.allowed,
          );
          final snapshots = _signinSnapshots(expectedAction);
          var prepareCalls = 0;
          var commitCalls = 0;
          var refreshCalls = 0;
          final intent = WriteIntent(
            intentId: 'signin-intent',
            operation: WriteOperation.signinPerform,
            targetSummary: '每日课程',
            resolvedRoute: ConnectionMode.webvpn,
            warnings: const <String>['提交后请刷新今日课程状态确认结果'],
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
                    message: '上课结果已提交，请刷新确认',
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
              ),
            ),
          );
          await tester.tap(find.byIcon(UiDestination.study.icon));
          await tester.pumpAndSettle();
          await openFeature(tester, FeatureId.signin);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '上课'));
          await tester.pumpAndSettle();
          expect(prepareCalls, 1);
          expect(commitCalls, 1);
          expect(refreshCalls, 1);
        }),
  );

  testWidgets(
    '每日课程点二维码打开面板且不触发写入',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 29, 0, 10)), () async {
          final snapshots = _signinSnapshots(
            const SigninPerformAction(
              scheduleId: 'schedule-7',
              eligibility: ActionEligibility.allowed,
            ),
          );
          var prepareCalls = 0;
          var commitCalls = 0;
          final reads = <(String, Duration)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: UbaaTheme.light(),
              home: coordinatedShell(
                user: const UserSummary(username: 'student'),
                snapshots: snapshots,
                routePolicy: RoutePolicy.auto,
                onRefresh: () async {},
                onRetryFeature: (_) async {},
                onFetchSigninQr: (scheduleId, offset) async {
                  reads.add((scheduleId, offset));
                  return '合成二维码';
                },
                onPrepareSigninWrite: (_) async {
                  prepareCalls++;
                  throw StateError('二维码入口不应准备写入');
                },
                onCommitWrite: (_) async {
                  commitCalls++;
                  throw StateError('二维码入口不应提交写入');
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
          await tester.tap(find.byTooltip('上课二维码'));
          await tester.pumpAndSettle();
          expect(find.byType(SigninQrSheet), findsWidgets);
          expect(reads, [('schedule-7', Duration.zero)]);
          expect(prepareCalls, 0);
          expect(commitCalls, 0);
          await tester.pumpWidget(const SizedBox());
        }),
  );
}

Map<FeatureId, FeatureSnapshot> _signinSnapshots(SigninPerformAction action) =>
    {
      FeatureId.signin: FeatureSnapshot(
        feature: FeatureId.signin,
        status: FeatureLoadStatus.success,
        details: [
          FeatureDetail(
            title: '每日课程',
            presentation: const SigninPresentation(
              courseId: '展示课程编号',
              classBeginTime: '08:00',
              classEndTime: '09:40',
              signStatus: 0,
            ),
            fields: const [
              FeatureField(label: '课程 ID', value: '误导目标'),
              FeatureField(label: '上课状态', value: '已上课'),
            ],
            actions: [action],
          ),
        ],
      ),
    };

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
