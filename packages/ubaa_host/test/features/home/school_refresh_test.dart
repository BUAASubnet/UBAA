import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';

void main() {
  for (final route in ConnectionMode.values) {
    testWidgets('登录后直接进入日程，$route学校刷新覆盖全部来源及完整周表', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = _SchoolBackend(route);
      await tester.pumpWidget(
        UbaaAppHost(backend: backend, initialDestination: UiDestination.agenda),
      );
      await tester.pumpAndSettle();
      final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
      login.onUsernameChanged('synthetic-school');
      login.onPasswordChanged('synthetic-password');
      login.onSubmit();
      await tester.pumpAndSettle();
      expect(backend.signedIn, isTrue);
      expect(find.byType(UbaaMainShell), findsOneWidget);
      backend.features.clear();
      backend.queries.clear();

      final agenda = tester.widget<AgendaView>(find.byType(AgendaView));
      await agenda.onRefreshSchool!();
      await tester.pumpAndSettle();

      expect(
        backend.features,
        unorderedEquals([
          FeatureId.schedule,
          FeatureId.signin,
          FeatureId.spoc,
          FeatureId.judge,
          FeatureId.ygdk,
          FeatureId.exam,
        ]),
      );
      expect(
        backend.queries.map((q) => q.view),
        unorderedEquals([
          FeatureQueryView.bykcChosenCourses,
          FeatureQueryView.cgyyOrders,
          FeatureQueryView.cgyyOrders,
          FeatureQueryView.scheduleTerms,
          FeatureQueryView.scheduleWeeks,
          FeatureQueryView.scheduleWeek,
        ]),
      );
      final weekly = backend.queries.singleWhere(
        (q) => q.view == FeatureQueryView.scheduleWeek,
      );
      expect(weekly.term, 'synthetic-term');
      expect(weekly.week, 10);
      expect(
        backend.queries
            .where((q) => q.view == FeatureQueryView.cgyyOrders)
            .map((q) => (q.page, q.size)),
        [(0, 20), (1, 20)],
      );
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.agenda.term, 'synthetic-term');
      expect(shell.agendaSchoolRoute, route);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('日程学校刷新等待当前周课表保存后才完成', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _SchoolBackend(ConnectionMode.direct)
      ..signedIn = true
      ..weekGate = Completer<FeatureResult>();
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, initialDestination: UiDestination.agenda),
    );
    await tester.pumpAndSettle();
    var completed = false;
    final agenda = tester.widget<AgendaView>(find.byType(AgendaView));
    final refresh = agenda.onRefreshSchool!().then((_) {
      completed = true;
    });
    await tester.pumpAndSettle();
    expect(
      backend.queries.any((q) => q.view == FeatureQueryView.scheduleWeek),
      isTrue,
    );
    expect(completed, isFalse);
    backend.weekGate!.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    await refresh;
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

class _SchoolBackend
    implements UbaaBackend, FeatureQueryBackend, RouteSettingsBackend {
  _SchoolBackend(this.route);
  final ConnectionMode route;
  bool signedIn = false;
  final features = <FeatureId>[];
  final queries = <FeatureQuery>[];
  Completer<FeatureResult>? weekGate;

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async =>
      signedIn ? const UserSummary(username: 'synthetic-school') : null;
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: route == ConnectionMode.direct
        ? RoutePolicy.direct
        : RoutePolicy.webvpn,
    activeRoutes: signedIn ? [route] : [],
  );
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    features.add(feature);
    return FeatureResult.empty(resolvedRoute: route);
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (query.view == FeatureQueryView.scheduleWeek && weekGate != null) {
      return weekGate!.future;
    }
    return switch (query.view) {
      FeatureQueryView.cgyyOrders => FeatureResult.success(
        resolvedRoute: route,
        details: List.generate(
          query.page == 0 ? 20 : 1,
          (i) => FeatureDetail(title: '合成预约${query.page * 20 + i}'),
        ),
        pagination: FeaturePagination(
          page: query.page + 1,
          size: 20,
          total: 21,
          totalPages: 2,
        ),
      ),
      FeatureQueryView.scheduleTerms => FeatureResult.success(
        resolvedRoute: route,
        details: const [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(
              code: 'synthetic-term',
              selected: true,
              index: 0,
            ),
          ),
        ],
      ),
      FeatureQueryView.scheduleWeeks => FeatureResult.success(
        resolvedRoute: route,
        details: const [
          FeatureDetail(
            title: '合成教学周',
            presentation: WeekPresentation(
              requestTerm: 'synthetic-term',
              responseTerm: 'synthetic-term',
              number: 10,
              current: true,
              startDate: '2026-11-02',
              endDate: '2026-11-08',
            ),
          ),
        ],
      ),
      _ => FeatureResult.empty(resolvedRoute: route),
    };
  }
}
