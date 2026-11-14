import 'package:ubaa_ui/src/features/home/shell_helpers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/shared/sync_status.dart';

void main() {
  test('完整混合来源不提示异常，渐进读取先展示进度', () {
    HomeState home(bool refining, bool complete, {bool offline = false}) =>
        HomeState(
          offline: offline,
          now: DateTime(2026),
          sources: {
            FeatureId.judge: FeatureSnapshot(
              feature: FeatureId.judge,
              status: refining
                  ? FeatureLoadStatus.loading
                  : FeatureLoadStatus.success,
              refining: refining,
              evidence: DataEvidence(
                accountId: 'synthetic',
                origin: DataOrigin.mixed,
                fetchedAt: DateTime(2026),
                complete: complete,
                savedForOffline: true,
              ),
            ),
          },
          schedule: const HomeScheduleState(
            date: '2026-01-01',
            snapshot: FeatureSnapshot(feature: FeatureId.schedule),
          ),
        );
    expect(homeSyncNotice(home(false, true)), isNull);
    expect(homeSyncNotice(home(true, false, offline: true)), '离线，显示已保存数据');
    expect(homeSyncNotice(home(true, false)), '正在更新希冀作业');
    expect(homeSyncNotice(home(false, false)), '部分数据未更新完整');
  });
  testWidgets('首页分别显示缓存、失败和恢复状态，刷新期间显示更新中', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 11, 14, 9);
    final old = now.subtract(const Duration(days: 1));
    final cached = DataEvidence(
      accountId: 'synthetic',
      origin: DataOrigin.persisted,
      fetchedAt: old,
      complete: true,
      savedForOffline: true,
    );
    Future<void> mount({
      bool cache = false,
      bool failed = false,
      bool busy = false,
      bool incomplete = false,
    }) async {
      final sources = {
        FeatureId.exam: FeatureSnapshot(
          feature: FeatureId.exam,
          status: failed ? FeatureLoadStatus.failure : FeatureLoadStatus.empty,
          error: failed
              ? const UiError(
                  code: UbaaErrorCode.networkError,
                  title: '连接失败',
                  message: '合成网络错误',
                )
              : null,
          updatedAt: now,
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: UbaaMainShell(
            user: null,
            snapshots: sources,
            routePolicy: RoutePolicy.auto,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) async {},
            homeState: HomeState(
              now: now,
              sources: sources,
              schedule: const HomeScheduleState(
                date: '2026-11-14',
                snapshot: FeatureSnapshot(feature: FeatureId.schedule),
              ),
              week: incomplete
                  ? FeatureResult.success(
                      evidence: DataEvidence(
                        accountId: 'synthetic',
                        origin: DataOrigin.online,
                        fetchedAt: now,
                        complete: false,
                        savedForOffline: false,
                      ),
                    )
                  : cache
                  ? FeatureResult.success(evidence: cached)
                  : null,
              updatedAt: now,
              busy: busy,
              projected: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    Finder statusText(String value) => find.descendant(
      of: find.byType(UiSyncStatus),
      matching: find.text(value),
    );
    await withClock(Clock.fixed(now), () async {
      await mount(cache: true);
      expect(statusText('部分数据使用缓存'), findsNothing);
      await mount(cache: true, failed: true);
      expect(statusText('部分更新失败'), findsOneWidget);
      await tester.tap(statusText('部分更新失败'));
      await tester.pumpAndSettle();
      expect(find.text('${FeatureId.exam.title}：更新失败：连接失败'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await mount(cache: true, failed: true, busy: true);
      expect(statusText('更新中'), findsOneWidget);
      await mount(incomplete: true);
      expect(statusText('部分数据未更新完整'), findsOneWidget);
      await mount();
      expect(
        find.descendant(
          of: find.byType(UiSyncStatus),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });
  });
}
