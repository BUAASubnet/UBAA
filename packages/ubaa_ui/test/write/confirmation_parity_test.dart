import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('已经提交后跨过准备期限仍显示忙碌而非意图过期', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WriteConfirmationView(
            intent: intent(
              expires: DateTime.now().add(const Duration(seconds: 2)),
            ),
            isSubmitting: true,
            onCancel: () {},
            onConfirm: () async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('意图已过期'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('确认页仅顶栏实际路线并以取消返回代替侧栏和刷新', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(shell(WritePhase.ready, () async => cancelled++));
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('刷新'), findsNothing);
    expect(find.text('实际路线'), findsNothing);
    expect(find.byTooltip('实际路线：直连'), findsOneWidget);
    await tester.tap(find.byTooltip('取消并返回'));
    await tester.pumpAndSettle();
    expect(cancelled, 1);
  });
  testWidgets('确认页系统返回调用取消，忙碌各阶段禁止返回与提交', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(shell(WritePhase.ready, () async => cancelled++));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    for (final phase in [
      WritePhase.committing,
      WritePhase.cancelling,
      WritePhase.readingBack,
    ]) {
      await tester.pumpWidget(shell(phase, () async => cancelled++));
      await tester.pump();
      final back = tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '取消并返回'),
      );
      expect(back.onPressed, isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(cancelled, 1);
    }
  });
  testWidgets('停留确认页跨过原意图有效期会自动禁用提交且可取消', (tester) async {
    var confirms = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WriteConfirmationView(
            intent: intent(
              expires: DateTime.now().add(const Duration(seconds: 2)),
            ),
            onCancel: () {},
            onConfirm: () async => confirms++,
          ),
        ),
      ),
    );
    expect(find.text('确认提交'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('意图已过期'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(confirms, 0);
  });
}

WriteIntent intent({DateTime? expires}) => WriteIntent(
  intentId: 'synthetic-confirmation',
  operation: WriteOperation.signinPerform,
  targetSummary: '合成课程',
  resolvedRoute: ConnectionMode.direct,
  warnings: const [],
  expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 5)),
  requestDigest: 'synthetic-digest',
);
Widget shell(WritePhase phase, Future<void> Function() cancel) => MaterialApp(
  home: UbaaMainShell(
    user: const UserSummary(username: 'synthetic-account'),
    snapshots: {
      for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
    },
    routePolicy: RoutePolicy.webvpn,
    telemetryEnabled: false,
    writeState: WriteState(phase: phase, intent: intent()),
    onCancelWrite: cancel,
    onConfirmWrite: () async => null,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  ),
);
