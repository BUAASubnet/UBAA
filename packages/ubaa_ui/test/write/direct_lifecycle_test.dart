import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/navigation.dart';
import '../support/write_harness.dart';

void main() {
  for (final expired in [false, true]) {
    testWidgets(
      expired ? 'prepare 后过期自动丢弃意图并提示，可重新发起' : '提交期间点击其他写按钮不发起第二次请求',
      (tester) async {
        final gate = Completer<WriteCommitResult>();
        var prepares = 0;
        var commits = 0;
        final discarded = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: coordinatedShell(
              user: const UserSummary(username: 'synthetic'),
              snapshots: {
                for (final feature in FeatureId.values)
                  feature: FeatureSnapshot(
                    feature: feature,
                    status: FeatureLoadStatus.success,
                    details: feature == FeatureId.bykc
                        ? const [
                            FeatureDetail(
                              title: '合成课程',
                              actions: [
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
                                  requiresCoordinates: false,
                                ),
                              ],
                            ),
                          ]
                        : const [],
                  ),
              },
              routePolicy: RoutePolicy.direct,
              telemetryEnabled: false,
              onRefresh: () async {},
              onRetryFeature: (_) async {},
              onLogout: () async {},
              onLogoutAndClearAccount: () async {},
              onRoutePolicyChanged: (_) {},
              onTelemetryChanged: (_) {},
              onPrepareBykcSignWrite: (_) async {
                prepares++;
                return WriteIntent(
                  intentId: 'synthetic-$prepares',
                  operation: WriteOperation.bykcSignCourse,
                  targetSummary: '合成签到',
                  resolvedRoute: ConnectionMode.direct,
                  warnings: const [],
                  expiresAt: DateTime.now().add(
                    Duration(minutes: expired ? -1 : 2),
                  ),
                  requestDigest: 'synthetic',
                );
              },
              onCommitWrite: (_) {
                commits++;
                return gate.future;
              },
              onDiscardWriteIntent: (id) async {
                discarded.add(id);
              },
            ),
          ),
        );
        await openFeature(tester, FeatureId.bykc);
        await tester.pumpAndSettle();
        await tester.tap(find.text('博雅签到'));
        await tester.pump();
        if (expired) {
          await tester.pumpAndSettle();
          expect(prepares, 1);
          expect(commits, 0);
          expect(discarded, ['synthetic-1']);
          expect(find.text('博雅签到未完成，请刷新后重试。'), findsOneWidget);
          await tester.tap(find.text('博雅签退'));
          await tester.pumpAndSettle();
          expect(prepares, 2);
          expect(discarded, ['synthetic-1', 'synthetic-2']);
          expect(commits, 0);
        } else {
          await tester.tap(find.text('博雅签退'));
          await tester.pump();
          expect(prepares, 1);
          expect(commits, 1);
          expect(discarded, isEmpty);
          gate.complete(
            const WriteCommitResult(
              operation: WriteOperation.bykcSignCourse,
              success: true,
              message: '合成签到成功',
              outcomeUnknown: false,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('合成签到成功'), findsOneWidget);
        }
      },
    );
  }
}
