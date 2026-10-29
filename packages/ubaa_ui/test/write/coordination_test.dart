import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

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
      await openFeature(tester, FeatureId.bykc);
      await tester.pumpAndSettle();
      expect(find.text('选课'), findsNothing);
    });
  }
}
