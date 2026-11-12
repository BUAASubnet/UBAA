import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';
import 'package:ubaa_ui/src/common/feature_detail.dart';
import '../support/navigation.dart';

void main() {
  for (final end in ['总页数', '空页', '重复课程']) {
    testWidgets('博雅到达$end后显示底线，反复触底不再请求，刷新后可以继续', (tester) async {
      final key = GlobalKey<_HarnessState>();
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: _Harness(key: key),
        ),
      );
      final state = key.currentState!;
      state.endPage = end;
      state.total = end == '总页数' ? 20 : 100;
      await tester.pumpAndSettle();
      await openFeature(tester, FeatureId.bykc);
      final list = find.byType(ListView).last;
      for (var i = 0; i < 4; i++) {
        await tester.drag(list, const Offset(0, -3000));
        await tester.pumpAndSettle();
      }
      expect(state.requests.map((q) => q.page), [2]);
      expect(find.text('没有更多课程').hitTestable(), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      final scroll = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.text('没有更多课程').hitTestable(),
        findsNothing,
        reason: '底线随列表滚动，不固定占用正文',
      );
      state.endPage = null;
      state.total = 30;
      await tester.tap(find.byTooltip('刷新当前查询'));
      await tester.pumpAndSettle();
      expect(state.requests.map((q) => q.page), [2, 1, 2]);
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(state.requests.map((q) => q.page), [2, 1, 2, 3]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('整页课程被本地筛选隐藏时继续查询后页', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
    final state = key.currentState!;
    state.total = 30;
    state.hidePageTwo = true;
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2, 3]);
    await tester.scrollUntilVisible(
      find.text('没有更多课程'),
      300,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('没有更多课程').hitTestable(), findsOneWidget);
    expect(find.text('项目29').hitTestable(), findsOneWidget);
  });

  testWidgets('空的完整在线列表显示底线，缓存和刷新失败不显示底线', (tester) async {
    for (final kind in ['在线空列表', '缓存', '刷新中', '失败', '不完整']) {
      final snapshot = FeatureSnapshot(
        feature: FeatureId.bykc,
        status: switch (kind) {
          '在线空列表' => FeatureLoadStatus.empty,
          '刷新中' => FeatureLoadStatus.loading,
          '失败' => FeatureLoadStatus.stale,
          _ => FeatureLoadStatus.success,
        },
        pagination: FeaturePagination(
          page: 1,
          size: 8,
          total: kind == '在线空列表' ? 80 : 0,
        ),
        details: kind == '在线空列表'
            ? []
            : const [
                FeatureDetail(
                  title: '合成课程',
                  presentation: BykcCoursePresentation(
                    id: 1,
                    courseName: '合成课程',
                    status: BykcCourseStatus.available,
                  ),
                ),
              ],
        evidence: DataEvidence(
          accountId: 'synthetic',
          origin: kind == '缓存' ? DataOrigin.persisted : DataOrigin.online,
          fetchedAt: DateTime(2026),
          complete: kind != '不完整',
          savedForOffline: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailView(
              feature: FeatureId.bykc,
              snapshot: snapshot,
              bykcFilters: BykcCourseFilters(),
              onBykcFiltersChanged: (_) {},
              onBack: () {},
              onRetry: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('没有更多课程').hitTestable(),
        kind == '在线空列表' ? findsOneWidget : findsNothing,
        reason: kind,
      );
    }
  });

  testWidgets('同账号后台刷新保留分页内容、滚动位置和当前查询', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scroll).position.pixels;
    final state = key.currentState!;
    final reads = state.requests.length;
    state.sessionRefresh();
    await tester.pumpAndSettle();
    expect(state.requests.length, reads);
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(position, 1),
    );
    expect(find.text('列表需要更新'), findsNothing);
    await state.read(FeatureId.bykc, state.requests.last);
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(position, 1),
      reason: '恢复响应到达后也必须保留多页列表的滚动位置',
    );
    final restored = tester.state<FeatureReadNavigatorState>(
      find.byType(FeatureReadNavigator),
    );
    expect(restored.currentFrame.snapshot.details, hasLength(20));
    expect(
      restored.currentFrame.snapshot.details.every(
        (item) => item.title.startsWith('新项目'),
      ),
      isTrue,
    );
  });

  testWidgets('滚动追加保留前页，失败显式重试，详情返回保留位置，刷新保留已加载范围', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final state = key.currentState!;
    final list = find.byType(ListView).last;
    final scroll = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    state.failNext = true;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2]);
    expect(find.text('重试'), findsOneWidget);
    final position = tester.state<ScrollableState>(scroll).position;
    final beforeRetry = position.pixels;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2, 2]);
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(beforeRetry, 1),
    );
    await tester.scrollUntilVisible(find.text('项目12'), 250, scrollable: scroll);
    final beforeDetail = tester.state<ScrollableState>(scroll).position.pixels;
    await tester.tap(find.text('项目12'));
    await tester.pumpAndSettle();
    expect(find.text('合成详情'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final restored = tester.state<ScrollableState>(scroll).position;
    expect(restored.pixels, closeTo(beforeDetail, 1));
    restored.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('项目0'), findsOneWidget);
    final beforeRefresh = state.requests.length;
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(
      state.requests.skip(beforeRefresh).map((q) => q.page),
      [1, 2],
      reason: '刷新从首页开始复核已经显示的两页',
    );
    expect(find.text('项目0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('追加在途重复滚动只请求一次，清理缓存拒绝迟到追加并等待显式刷新', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final state = key.currentState!;
    state.gate = Completer<void>();
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(list, const Offset(0, -100));
    await tester.pump();
    expect(state.requests.length, 1);
    state.invalidate();
    await tester.pump();
    state.gate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.requests.map((q) => q.page), [2]);
    expect(find.text('项目10'), findsNothing);
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2, 1]);
    expect(find.text('新项目0'), findsOneWidget);
    expect(find.text('项目10'), findsNothing, reason: '迟到的旧代次不能进入新列表');
    expect(tester.takeException(), isNull);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final requests = <FeatureQuery>[];
  Completer<void>? gate;
  bool failNext = false, hidePageTwo = false;
  String? endPage;
  int total = 20;
  int revision = 0, epoch = 0, contentEpoch = 0;
  late FeatureSnapshot snapshot = result(const FeatureQuery());
  FeatureSnapshot result(FeatureQuery query) => FeatureSnapshot(
    feature: FeatureId.bykc,
    status: FeatureLoadStatus.success,
    resolvedRoute: ConnectionMode.direct,
    readContext: FeatureReadContext(query: query, requestRevision: revision),
    pagination: query.view == FeatureQueryView.bykcDetail
        ? null
        : FeaturePagination(
            page: query.page <= 0 ? 1 : query.page,
            size: 10,
            total: total,
          ),
    details: query.view == FeatureQueryView.bykcDetail
        ? const [FeatureDetail(title: '合成详情')]
        : query.page > 1 && endPage == '空页'
        ? []
        : [
            for (
              var i =
                  ((query.page <= 0 || endPage == '重复课程' ? 1 : query.page) -
                      1) *
                  10;
              i < (query.page <= 0 || endPage == '重复课程' ? 1 : query.page) * 10;
              i++
            )
              FeatureDetail(
                title: '${epoch == 0 ? '' : '新'}项目$i',
                presentation: BykcCoursePresentation(
                  id: i + 1,
                  courseName: '${epoch == 0 ? '' : '新'}项目$i',
                  status: hidePageTwo && query.page == 2
                      ? BykcCourseStatus.ended
                      : BykcCourseStatus.available,
                ),
                readNavigation: FeatureReadNavigation(
                  feature: FeatureId.bykc,
                  query: FeatureQuery(
                    view: FeatureQueryView.bykcDetail,
                    courseId: '$i',
                  ),
                ),
              ),
          ],
  );
  void invalidate() => setState(() {
    epoch++;
    contentEpoch++;
  });
  void sessionRefresh() => setState(() => epoch++);
  Future<void> read(FeatureId id, FeatureQuery query) async {
    requests.add(query);
    revision++;
    final next = result(query);
    setState(
      () => snapshot = snapshot.copyWith(
        status: FeatureLoadStatus.loading,
        readContext: next.readContext,
      ),
    );
    if (gate != null) await gate!.future;
    setState(() {
      snapshot = failNext
          ? next.copyWith(
              status: FeatureLoadStatus.failure,
              clearDetails: true,
              error: const UiError(
                code: UbaaErrorCode.networkError,
                title: '合成错误',
                message: '失败',
              ),
            )
          : next;
      failNext = false;
    });
  }

  @override
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'synthetic'),
    readCacheEpoch: epoch,
    businessCacheEpoch: contentEpoch,
    snapshots: {
      for (final id in FeatureId.values)
        id: id == FeatureId.bykc ? snapshot : FeatureSnapshot(feature: id),
    },
    routePolicy: RoutePolicy.auto,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onFeatureQuery: read,
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
  );
}
