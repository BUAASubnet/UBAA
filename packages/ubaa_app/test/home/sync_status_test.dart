import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 9);
  final old = now.subtract(const Duration(days: 1));
  const failure = UiError(
    code: UbaaErrorCode.networkError,
    title: '连接失败',
    message: '合成网络错误',
  );
  DataEvidence evidence(DateTime at, DataOrigin origin) => DataEvidence(
    accountId: 'synthetic',
    origin: origin,
    fetchedAt: at,
    complete: true,
    savedForOffline: true,
  );

  HomeCoordinator model(
    Map<FeatureId, FeatureSnapshot> sources, {
    bool cachedWeek = true,
  }) {
    final result = HomeCoordinator(
      now: () => now,
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      readCachedWeek: (_) async => cachedWeek
          ? FeatureResult.success(evidence: evidence(old, DataOrigin.persisted))
          : null,
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (_) async => HomeTodoProjection(const []),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
    );
    addTearDown(result.dispose);
    result.update(
      owner: 'synthetic',
      snapshots: sources,
      epoch: 0,
      agenda: 0,
      active: true,
      online: false,
      blocked: false,
      foreground: false,
      readDays: false,
    );
    return result;
  }

  test('教学周仍为旧缓存时，首页时间跟随最新成功取得的来源', () async {
    final home = model({
      FeatureId.exam: FeatureSnapshot(
        feature: FeatureId.exam,
        status: FeatureLoadStatus.success,
        updatedAt: now,
        evidence: evidence(now, DataOrigin.online),
      ),
    });
    await home.flushProjection();
    expect(home.state.updatedAt, now);
    expect(home.state.week!.evidence!.fetchedAt, old);
    expect(home.state.week!.evidence!.origin, DataOrigin.persisted);
  });

  test('部分失败保留旧内容，同时保留其他来源的新读取时间', () async {
    final home = model({
      FeatureId.exam: FeatureSnapshot(
        feature: FeatureId.exam,
        status: FeatureLoadStatus.stale,
        error: failure,
        updatedAt: old,
        evidence: evidence(old, DataOrigin.persisted),
      ),
      FeatureId.spoc: FeatureSnapshot(
        feature: FeatureId.spoc,
        status: FeatureLoadStatus.empty,
        updatedAt: now,
      ),
    });
    await home.flushProjection();
    expect(home.state.updatedAt, now);
    expect(home.state.sources[FeatureId.exam]!.error, failure);
    expect(home.state.sources[FeatureId.exam]!.updatedAt, old);
  });

  test('没有取得新数据的失败不能推进首页更新时间', () async {
    final home = model({
      FeatureId.exam: FeatureSnapshot(
        feature: FeatureId.exam,
        status: FeatureLoadStatus.failure,
        error: failure,
        updatedAt: now,
      ),
    });
    await home.flushProjection();
    expect(home.state.updatedAt, old);
  });

  test('首次读取失败且没有缓存时不显示更新时间', () async {
    final home = model({
      FeatureId.exam: FeatureSnapshot(
        feature: FeatureId.exam,
        status: FeatureLoadStatus.failure,
        error: failure,
        updatedAt: now,
      ),
    }, cachedWeek: false);
    await home.flushProjection();
    expect(home.state.updatedAt, isNull);
  });
}
