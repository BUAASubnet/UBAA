import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final missing in ['prepare', 'cancel', 'confirm']) {
    testWidgets('缺少 $missing 写命令时关闭领域准备入口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: UbaaMainShell(
            user: const UserSummary(username: 'student'),
            snapshots: {
              for (final feature in FeatureId.values)
                feature: FeatureSnapshot(
                  feature: feature,
                  status: FeatureLoadStatus.success,
                  details: feature == FeatureId.bykc
                      ? const [
                          FeatureDetail(
                            title: '课程',
                            actions: [
                              BykcSelectAction(
                                courseId: 42,
                                eligibility: ActionEligibility.allowed,
                              ),
                            ],
                          ),
                        ]
                      : const [],
                ),
            },
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            onPrepareBykcWrite: (_, _) async => throw StateError('不应准备'),
            onRunWritePrepare: missing == 'prepare'
                ? null
                : (prepare, {required expectedOperation}) async => prepare(),
            onCancelWrite: missing == 'cancel' ? null : () async {},
            onConfirmWrite: missing == 'confirm' ? null : () async => null,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('博雅课程'));
      await tester.pumpAndSettle();
      expect(find.text('准备选课'), findsNothing);
    });
  }

  testWidgets('确认页完全消费宿主写状态并将确认命令交回宿主', (tester) async {
    var confirmations = 0;
    final intent = WriteIntent(
      intentId: 'host-owned-intent',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '由宿主保存的确认目标',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );

    Widget shell(WriteState state) => MaterialApp(
      theme: UbaaTheme.light(),
      home: UbaaMainShell(
        user: const UserSummary(username: 'student'),
        snapshots: <FeatureId, FeatureSnapshot>{
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(feature: feature),
        },
        routePolicy: RoutePolicy.direct,
        telemetryEnabled: false,
        writeState: state,
        onConfirmWrite: () async {
          confirmations++;
          return null;
        },
        onCancelWrite: () async {},
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    );

    await tester.pumpWidget(
      shell(WriteState(phase: WritePhase.ready, intent: intent)),
    );
    expect(find.text('由宿主保存的确认目标'), findsOneWidget);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    expect(find.text('由宿主保存的确认目标'), findsOneWidget);

    await tester.pumpWidget(
      shell(WriteState(phase: WritePhase.committing, intent: intent)),
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(shell(const WriteState.idle()));
    await tester.pumpAndSettle();
    expect(find.text('由宿主保存的确认目标'), findsNothing);
    expect(confirmations, 1);
  });
}
