import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';

void main() {
  testWidgets('博雅首屏不批量预取，重入保留已加载页且不请求网络', (tester) async {
    final h = await mount(tester);
    expect(h.requests, [1]);
    await h.more!();
    await tester.pumpAndSettle();
    expect(h.requests, [1, 2]);
    h.key.currentState!.goBack();
    await tester.pumpAndSettle();
    expect(h.visible.value, isFalse);
    h.visible.value = true;
    h.key.currentState!.openList();
    await tester.pumpAndSettle();
    expect(h.requests, [1, 2]);
    expect(h.shown.details.map((d) => d.title), ['旧课程1', '旧课程2']);
  });

  testWidgets('刷新后总页数减少时不请求已经不存在的后页', (tester) async {
    final h = await mount(tester);
    await h.more!();
    await tester.pumpAndSettle();
    h.refreshing = true;
    h.total = 1;
    final refresh = h.key.currentState!.refreshCurrent();
    await tester.pumpAndSettle();
    h.first.complete();
    await refresh;
    await tester.pumpAndSettle();
    expect(h.requests, [1, 2, 1]);
    expect(h.shown.details.map((d) => d.title), ['新课程1']);
    expect(h.error, isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('博雅多页刷新不被缓存首屏或中间页替换，失败=$fail', (tester) async {
      final h = await mount(tester);
      await h.more!();
      await tester.pumpAndSettle();
      h.refreshing = true;
      h.fail = fail;
      final refresh = h.key.currentState!.refreshCurrent();
      await tester.pumpAndSettle();
      expect(h.shown.details.map((d) => d.title), ['旧课程1', '旧课程2']);
      expect(h.shown.details.expand((d) => d.actions), isEmpty);
      h.first.complete();
      await refresh;
      await tester.pumpAndSettle();
      expect(h.requests, [1, 2, 1, 2]);
      expect(h.shown.details.map((d) => d.title), ['旧课程1', '旧课程2']);
      h.second.complete();
      await tester.pumpAndSettle();
      expect(
        h.shown.details.map((d) => d.title),
        fail ? ['旧课程1', '旧课程2'] : ['新课程1', '新课程2'],
      );
      expect(h.error, fail ? isNotNull : isNull);
      if (fail) {
        expect(h.shown.details.expand((d) => d.actions), isEmpty);
        h.fail = false;
        await h.more!();
        await tester.pumpAndSettle();
        expect(h.requests, [1, 2, 1, 2, 1, 2]);
        expect(h.shown.details.map((d) => d.title), ['新课程1', '新课程2']);
        expect(h.error, isNull);
      } else {
        expect(h.shown.details.expand((d) => d.actions), hasLength(2));
      }
    });
  }
}

class Harness {
  final key = GlobalKey<FeatureReadNavigatorState>();
  final visible = ValueNotifier(true);
  final snapshot = ValueNotifier(FeatureSnapshot(feature: FeatureId.bykc));
  final requests = <int>[];
  final first = Completer<void>(), second = Completer<void>();
  bool refreshing = false, fail = false;
  int total = 2;
  late FeatureSnapshot shown;
  String? error;
  Future<void> Function()? more;
  FeatureSnapshot page(FeatureQuery query, String prefix) => FeatureSnapshot(
    feature: FeatureId.bykc,
    status: FeatureLoadStatus.success,
    resolvedRoute: ConnectionMode.direct,
    readContext: FeatureReadContext(
      query: query,
      requestRevision: requests.length,
    ),
    pagination: FeaturePagination(page: query.page, size: 1, total: total),
    details: [
      FeatureDetail(
        title: '${prefix}课程${query.page}',
        presentation: BykcCoursePresentation(
          id: query.page,
          courseName: '${prefix}课程${query.page}',
          status: BykcCourseStatus.available,
        ),
        actions: [
          BykcSelectAction(
            courseId: query.page,
            eligibility: ActionEligibility.allowed,
          ),
        ],
      ),
    ],
  );
  Future<void> read(FeatureQuery query) async {
    requests.add(query.page);
    if (refreshing) {
      final cached = CachedFeatureProjection(
        feature: FeatureId.bykc,
        accountId: 'synthetic',
        route: ConnectionMode.direct,
        fetchedAt: DateTime(2026),
        complete: true,
        query: query,
        details: page(query, '缓存').details,
        pagination: page(query, '缓存').pagination,
      ).toSnapshot();
      snapshot.value = cached.copyWith(
        status: FeatureLoadStatus.loading,
        readContext: FeatureReadContext(
          query: query,
          requestRevision: requests.length,
        ),
      );
      await (query.page == 1 ? first : second).future;
    }
    snapshot.value = page(query, refreshing ? '新' : '旧').copyWith(
      status: refreshing && fail && query.page == 2
          ? FeatureLoadStatus.failure
          : FeatureLoadStatus.success,
    );
  }
}

Future<Harness> mount(WidgetTester tester) async {
  final h = Harness();
  addTearDown(h.snapshot.dispose);
  addTearDown(h.visible.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: h.visible,
        builder: (_, visible, _) => TickerMode(
          enabled: visible,
          child: ValueListenableBuilder<FeatureSnapshot>(
            valueListenable: h.snapshot,
            builder: (_, snapshot, _) => FeatureReadNavigator(
              key: h.key,
              snapshot: snapshot,
              cacheEpoch: 0,
              initialHomeTarget: const FeatureReadNavigation(
                feature: FeatureId.bykc,
                query: FeatureQuery(page: 1),
              ),
              onExit: () => h.visible.value = false,
              onRetry: () async {},
              onVisibleSnapshot: (_, _) {},
              onQuery: h.read,
              pageBuilder: (page) {
                h.shown = page.snapshot;
                h.error = page.moreError;
                h.more = page.onLoadMore;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}
