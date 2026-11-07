import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/controller/fakes.dart';

void main() {
  for (final source in ['学校日程', '首页', '当前教学周']) {
    test('$source刷新等待学期查询时保留已知日程学期和路线', () async {
      final backend = _Backend();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.loadHomeSupplement(HomeSupplement.currentWeek);
      expect(controller.currentAgendaTerm, 'synthetic-term');
      expect(controller.currentAgendaRoute, ConnectionMode.direct);
      final observed = <(String, ConnectionMode?)>[];
      controller.addListener(() {
        observed.add((
          controller.currentAgendaTerm,
          controller.currentAgendaRoute,
        ));
      });
      backend.termsGate = Completer<void>();
      final refresh = switch (source) {
        '学校日程' => controller.refreshSchoolAgenda(),
        '首页' => controller.refreshHome().then((_) async {
          await controller.loadHomeSupplement(HomeSupplement.currentWeek);
        }),
        _ =>
          controller
              .loadHomeSupplement(
                HomeSupplement.currentWeek,
                forceRefresh: true,
              )
              .then((_) {}),
      };
      expect(controller.currentAgendaTerm, 'synthetic-term');
      await backend.termsStarted.future;
      expect(controller.currentAgendaTerm, 'synthetic-term');
      expect(controller.currentAgendaRoute, ConnectionMode.direct);
      backend.termsGate!.complete();
      await refresh;
      expect(controller.currentAgendaTerm, 'synthetic-term');
      expect(observed, everyElement(('synthetic-term', ConnectionMode.direct)));
    });
  }

  test('学期读取失败保留已知日程学期，确认新学期后更新', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadHomeSupplement(HomeSupplement.currentWeek);
    backend.failTerms = true;
    await controller.refreshSchoolAgenda();
    expect(controller.currentAgendaTerm, 'synthetic-term');
    expect(controller.currentAgendaRoute, ConnectionMode.direct);
    backend
      ..failTerms = false
      ..term = 'synthetic-next-term';
    await controller.refreshSchoolAgenda();
    expect(controller.currentAgendaTerm, 'synthetic-next-term');
    expect(controller.currentAgendaRoute, ConnectionMode.direct);
  });

  test('完整学校刷新与同代首页补充合并，周表完成后才结束', () async {
    final backend = _Backend()
      ..chosenGate = Completer<FeatureResult>()
      ..weekGate = Completer<FeatureResult>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    var completed = false;
    final refresh = controller.refreshSchoolAgenda().then((_) {
      completed = true;
    });
    final chosen = controller.loadHomeSupplement(
      HomeSupplement.bykcChosen,
      forceRefresh: true,
    );
    await backend.weekStarted.future;
    expect(
      backend.queries.where(
        (q) => q.view == FeatureQueryView.bykcChosenCourses,
      ),
      hasLength(1),
    );
    backend.chosenGate!.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    await chosen;
    expect(completed, isFalse);
    final epoch = controller.agendaProjectionEpoch;
    backend.weekGate!.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    await refresh;
    expect(completed, isTrue);
    expect(controller.agendaProjectionEpoch, greaterThan(epoch));
    expect(backend.orderPages, [0, 1, 2]);
    expect(controller.currentAgendaTerm, 'synthetic-term');
  });

  test('当前学期合理缺失时仍刷新独立来源，不猜学期或教学周', () async {
    final backend = _Backend()..noTerm = true;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshSchoolAgenda();
    expect(controller.currentAgendaTerm, isEmpty);
    expect(
      backend.queries.map((q) => q.view),
      isNot(contains(FeatureQueryView.scheduleWeeks)),
    );
    expect(
      backend.queries.map((q) => q.view),
      isNot(contains(FeatureQueryView.scheduleWeek)),
    );
    expect(backend.orderPages, [0, 1, 2]);
    expect(
      backend.features.toSet(),
      containsAll([
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.signin,
        FeatureId.exam,
        FeatureId.ygdk,
      ]),
    );
  });

  test('SPOC失败仍更新其余来源并等待周表，研讨室后页失败停止后续请求', () async {
    final backend = _Backend()
      ..failSpoc = true
      ..failOrderPage = true
      ..weekGate = Completer<FeatureResult>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    var completed = false;
    final refresh = controller.refreshSchoolAgenda().then((_) {
      completed = true;
    });
    await backend.failedPage.future;
    expect(completed, isFalse);
    backend.weekGate!.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    await refresh;
    expect(
      controller.homeSnapshots[FeatureId.spoc]!.error?.code,
      UbaaErrorCode.networkError,
    );
    expect(
      controller.homeSnapshots[FeatureId.signin]!.status,
      FeatureLoadStatus.empty,
    );
    expect(backend.orderPages, [0, 1]);
    expect(controller.exportDiagnostics(), contains('network_error'));
  });

  for (final transition in ['退出', '换路线']) {
    test('研讨室后页在途$transition后不续读其他页或交付日程更新', () async {
      final backend = _Backend()..orderPageGate = Completer<FeatureResult>();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final refresh = controller.refreshSchoolAgenda();
      await backend.secondPageStarted.future;
      if (transition == '退出') {
        await controller.logout();
      } else {
        await controller.setRoutePolicy(RoutePolicy.webvpn);
      }
      final epoch = controller.agendaProjectionEpoch;
      backend.orderPageGate!.complete(
        const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
      );
      await refresh;
      expect(backend.orderPages, [0, 1]);
      expect(controller.agendaProjectionEpoch, epoch);
      expect(controller.currentAgendaTerm, isEmpty);
    });
  }
}

class _Backend extends FixtureQueryBackend {
  _Backend() : super(onQuery: (_, _) => const FeatureResult.empty());
  final queries = <FeatureQuery>[];
  final features = <FeatureId>[];
  final weekStarted = Completer<void>();
  final secondPageStarted = Completer<void>();
  final failedPage = Completer<void>();
  final termsStarted = Completer<void>();
  Completer<FeatureResult>? chosenGate, weekGate, orderPageGate;
  Completer<void>? termsGate;
  bool noTerm = false, failSpoc = false, failOrderPage = false;
  bool failTerms = false;
  String term = 'synthetic-term';
  List<int> get orderPages => queries
      .where((q) => q.view == FeatureQueryView.cgyyOrders)
      .map((q) => q.page)
      .toList();

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-school');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    features.add(feature);
    if (feature == FeatureId.spoc && failSpoc) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (query.view == FeatureQueryView.scheduleTerms) {
      if (termsGate != null) {
        if (!termsStarted.isCompleted) termsStarted.complete();
        await termsGate!.future;
      }
      if (failTerms) throw const BackendException(UbaaErrorCode.networkError);
    }
    if (query.view == FeatureQueryView.bykcChosenCourses && chosenGate != null)
      return chosenGate!.future;
    if (query.view == FeatureQueryView.scheduleWeek) {
      if (!weekStarted.isCompleted) weekStarted.complete();
      if (weekGate != null) return weekGate!.future;
    }
    if (query.view == FeatureQueryView.cgyyOrders) {
      if (query.page == 1) {
        if (!secondPageStarted.isCompleted) secondPageStarted.complete();
        if (orderPageGate != null) return orderPageGate!.future;
        if (failOrderPage) {
          if (!failedPage.isCompleted) failedPage.complete();
          throw const BackendException(UbaaErrorCode.networkError);
        }
      }
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: List.generate(
          query.page < 2 ? 20 : 1,
          (i) => FeatureDetail(title: '合成预约${query.page * 20 + i}'),
        ),
        pagination: FeaturePagination(
          page: query.page + 1,
          size: 20,
          total: 41,
          totalPages: 3,
        ),
      );
    }
    return switch (query.view) {
      FeatureQueryView.scheduleTerms when !noTerm => FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(
              code: term,
              selected: true,
              index: 0,
            ),
          ),
        ],
      ),
      FeatureQueryView.scheduleWeeks => FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成教学周',
            presentation: WeekPresentation(
              requestTerm: term,
              responseTerm: term,
              number: 10,
              current: true,
              startDate: '2026-11-02',
              endDate: '2026-11-08',
            ),
          ),
        ],
      ),
      _ => const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    };
  }
}
