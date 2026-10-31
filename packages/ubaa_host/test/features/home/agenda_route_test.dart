import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final (from, to) in [
    (RoutePolicy.direct, RoutePolicy.webvpn),
    (RoutePolicy.webvpn, RoutePolicy.direct),
    (RoutePolicy.direct, RoutePolicy.auto),
  ]) {
    for (final fails in [false, true]) {
      testWidgets('$from→$to ${fails ? '回滚' : '成功'}后，相同来源也重新投影且旧签到只读', (
        tester,
      ) async {
        final backend = _Backend(from);
        await tester.pumpWidget(UbaaAppHost(backend: backend));
        await tester.pumpAndSettle();
        UbaaMainShell shell() =>
            tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
        expect(find.text('合成签到'), findsOneWidget);
        final source = shell().homeSnapshots![FeatureId.signin]!;
        final received = backend.projections;
        backend.waiting = Completer<void>();
        shell().onRoutePolicyChanged(to);
        await backend.started.future;
        await tester.pump();
        expect(shell().onProjectHomeTodos, isNull);
        expect(find.text('合成签到'), findsNothing);
        expect(backend.projections, received, reason: '切换窗口不进入纯投影后端');
        if (fails) {
          backend.waiting!.completeError(
            const BackendException(UbaaErrorCode.internalError),
          );
        } else {
          backend.waiting!.complete();
        }
        await tester.pumpAndSettle();
        expect(shell().onProjectHomeTodos, isNotNull);
        expect(
          identical(shell().homeSnapshots![FeatureId.signin], source),
          isTrue,
        );
        expect(backend.projections, greaterThan(received), reason: '来源未变也恢复投影');
        final keepsSource = fails || to == RoutePolicy.auto;
        expect(find.text('合成签到'), keepsSource ? findsOneWidget : findsNothing);
        final old = await shell().onProjectHomeTodos!(
          HomeTodoRequest(
            snapshots: {FeatureId.signin: source},
            now: DateTime.now(),
          ),
        );
        expect(old.todos.every((todo) => todo.signinAction == null), isTrue);
        await shell().onRetryFeature(FeatureId.signin);
        await tester.pumpAndSettle();
        expect(find.text('合成签到'), findsOneWidget);
        final fresh = await shell().onProjectHomeTodos!(
          HomeTodoRequest(
            snapshots: shell().homeSnapshots!,
            now: DateTime.now(),
          ),
        );
        expect(fresh.todos.single.signinAction?.scheduleId, 'synthetic-target');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

class _Backend extends DemoBackend implements RouteSettingsBackend {
  _Backend(this.policy);
  RoutePolicy policy;
  Completer<void>? waiting;
  final started = Completer<void>();
  int projections = 0;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-route-home');
  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: policy,
    activeRoutes: ConnectionMode.values,
  );
  @override
  Future<void> prepareLogin(RoutePolicy value) async {
    final gate = waiting;
    if (gate != null) {
      started.complete();
      await gate.future;
      waiting = null;
    }
    policy = value;
  }

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) {
    projections++;
    return super.projectHomeTodos(request);
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature != FeatureId.signin
      ? const FeatureResult.empty()
      : FeatureResult.success(
          resolvedRoute: policy == RoutePolicy.webvpn
              ? ConnectionMode.webvpn
              : ConnectionMode.direct,
          details: const [
            FeatureDetail(
              title: '合成签到',
              presentation: SigninPresentation(
                courseId: 'synthetic-course',
                classBeginTime: '12:00',
                classEndTime: '13:00',
                signStatus: 0,
              ),
              actions: [
                SigninPerformAction(
                  scheduleId: 'synthetic-target',
                  eligibility: ActionEligibility.allowed,
                ),
              ],
            ),
          ],
        );
}
