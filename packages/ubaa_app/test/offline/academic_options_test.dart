import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'startup_test.dart' as support;

void main() {
  test('首帧恢复之前学期和教学周选项可离线使用，明确刷新仍等待在线结果', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    FeatureResult? terms;
    unawaited(controller.loadAcademicTerms().then((value) => terms = value));
    for (var i = 0; i < 100 && terms == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(terms, isNotNull);
    expect(terms!.evidence!.origin, DataOrigin.persisted);
    final weeks = await controller.loadAcademicWeeks('2025-2026-1');
    expect(weeks.details.single.title, '第3周');
    expect(backend.authCalls, 0);
    controller.onHomeFirstFrame();
    final forced = await controller.loadAcademicTerms(forceRefresh: true);
    expect(forced.error, isNotNull);
  });
}

class _Backend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        ProgressiveReadBackend,
        RequiredSessionBackend,
        OfflineCacheBackend,
        OfflineQueryBackend {
  LocalAccount? account;
  int authCalls = 0;
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async => OfflineQueryRead(
    CachedFeatureProjection(
      feature: feature,
      query: query,
      accountId: account!.id,
      route: ConnectionMode.direct,
      fetchedAt: DateTime.utc(2026, 9, 1),
      complete: true,
      details: [
        FeatureDetail(
          title: query.view == FeatureQueryView.scheduleTerms ? '已保存学期' : '第3周',
        ),
      ],
    ),
  );
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    authCalls++;
    throw const BackendException(UbaaErrorCode.networkError);
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
