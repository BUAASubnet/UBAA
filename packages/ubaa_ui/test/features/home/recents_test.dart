import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/app/home.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';
import 'package:ubaa_ui/src/features/health_cloud/view.dart';
import 'package:ubaa_ui/src/shared/refresh.dart';

Future<void> mount(
  WidgetTester tester,
  String account,
  Future<List<FeatureId>> Function() load,
  Future<void> Function(List<FeatureId>) save, {
  ValueChanged<String>? onOpened,
  ReadHealthCloud? healthCloudRead,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UbaaMainShell(
        user: UserSummary(username: account),
        snapshots: {
          for (final f in FeatureId.values)
            f: FeatureSnapshot(feature: f, status: FeatureLoadStatus.empty),
        },
        routePolicy: RoutePolicy.auto,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onLoadRecentFeatures: load,
        onSaveRecentFeatures: save,
        onFeatureOpened: onOpened,
        healthCloudRead: healthCloudRead,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HomeView home(WidgetTester tester) =>
    tester.widget<HomeView>(find.byType(HomeView, skipOffstage: false));

void main() {
  testWidgets('恢复首页和切换分组不计打开，快捷入口、待办和校园服务每次打开各计一次', (tester) async {
    final opened = <String>[];
    await mount(
      tester,
      'fixture',
      () async => [FeatureId.exam],
      (_) async {},
      onOpened: opened.add,
    );
    final entry = find.byKey(const ValueKey('recent-exam'));
    expect(opened, isEmpty);
    for (var visits = 1; visits <= 2; visits++) {
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final page = find.byType(FeatureReadNavigator);
      await tester
          .widget<PullToRefresh>(
            find
                .descendant(of: page, matching: find.byType(PullToRefresh))
                .last,
          )
          .onRefresh();
      await tester.widget<FeatureReadNavigator>(page).onRetry();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(opened, List.filled(visits, 'exam'));
    }
    home(tester).onTodoTap(
      HomeTodo(
        id: 'fixture',
        title: '考试',
        subtitle: '',
        timeLabel: '',
        statusLabel: '',
        sortTime: DateTime(2026),
        feature: FeatureId.exam,
        navigation: const FeatureReadNavigation(
          feature: FeatureId.exam,
          query: FeatureQuery(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(UiDestination.campus.icon).hitTestable());
    await tester.pumpAndSettle();
    expect(opened, ['exam', 'exam', 'exam']);
    final drive = find.text('云盘').last;
    await tester.ensureVisible(drive);
    await tester.tap(drive);
    await tester.pumpAndSettle();
    expect(opened.last, 'bhpan');
    expect(opened, hasLength(4));
  });

  testWidgets('从校园每次进入健康云只计一次打开，页内读取不计', (tester) async {
    const latest = HealthCloudYear(2026, '2026-2027_1');
    const earlier = HealthCloudYear(2025, '2025-2026_1');
    final opened = <String>[];
    final reads = <String?>[];
    await mount(
      tester,
      'fixture',
      () async => [],
      (_) async {},
      onOpened: opened.add,
      healthCloudRead: (year) async {
        reads.add(year);
        if (reads.length == 3) throw StateError('合成读取失败');
        return HealthCloudPage(
          years: const [latest, earlier],
          selectedYear: year ?? latest.key,
          report: null,
          route: ConnectionMode.direct,
        );
      },
    );
    await tester.tap(find.byIcon(UiDestination.campus.icon).hitTestable());
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    final entry = find.text(healthCloudTitle);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(HealthCloudView), findsOneWidget);
    expect(opened, ['health_cloud']);

    await tester.tap(find.text('${earlier.year}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新体测成绩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(reads, [null, earlier.key, earlier.key, earlier.key]);
    expect(opened, ['health_cloud']);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(reads.last, isNull);
    expect(opened, ['health_cloud', 'health_cloud']);
  });

  testWidgets('同一本机账号资料更新保留常用功能，不重新读取偏好', (tester) async {
    var reads = 0;
    final profile = ValueNotifier(
      const UserSummary(
        username: 'f***r',
        schoolId: 'T***1',
        accountScope: 'local-fixture',
      ),
    );
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<UserSummary>(
          valueListenable: profile,
          builder: (_, user, _) => UbaaMainShell(
            user: user,
            snapshots: {
              for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
            },
            routePolicy: RoutePolicy.auto,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onLoadRecentFeatures: () async {
              reads++;
              return [FeatureId.grades, FeatureId.exam];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    profile.value = const UserSummary(
      username: 'fixture-user',
      schoolId: 'TEST-0001',
      accountScope: 'local-fixture',
    );
    await tester.pump();
    expect(home(tester).recentFeatures, [FeatureId.grades, FeatureId.exam]);
    expect(reads, 1);
  });

  testWidgets('迟到恢复合并到本轮访问之后，重复入口只保留最近位置', (tester) async {
    final pending = Completer<List<FeatureId>>();
    final saved = <List<FeatureId>>[];
    await mount(
      tester,
      'a',
      () => pending.future,
      (value) async => saved.add(value),
    );
    home(tester).onFeatureTap(FeatureId.exam);
    await tester.pumpAndSettle();
    pending.complete([FeatureId.grades, FeatureId.exam, FeatureId.spoc]);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [
      FeatureId.exam,
      FeatureId.grades,
      FeatureId.spoc,
    ]);
    expect(saved.last, [FeatureId.exam, FeatureId.grades, FeatureId.spoc]);
  });
  testWidgets('切换账号拒绝旧账号迟到记录，保存失败仍可导航', (tester) async {
    final first = Completer<List<FeatureId>>();
    await mount(tester, 'a', () => first.future, (_) async {});
    await mount(
      tester,
      'b',
      () async => [FeatureId.spoc],
      (_) async => throw StateError('合成失败'),
    );
    first.complete([FeatureId.exam]);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [FeatureId.spoc]);
    home(tester).onFeatureTap(FeatureId.grades);
    await tester.pumpAndSettle();
    expect(home(tester).recentFeatures, [FeatureId.grades, FeatureId.spoc]);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
