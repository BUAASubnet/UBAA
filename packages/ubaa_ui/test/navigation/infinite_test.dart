import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('滚动追加保留前页，失败显式重试，详情返回保留位置，刷新重置首屏', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
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
    expect(find.text('重试加载'), findsOneWidget);
    final position = tester.state<ScrollableState>(scroll).position;
    final beforeRetry = position.pixels;
    await tester.tap(find.text('重试加载'));
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
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(state.requests.last.page, 1);
    expect(find.text('项目0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('追加在途重复滚动只请求一次，缓存失效拒绝迟到追加', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
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
    expect(find.text('项目10'), findsNothing);
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
  bool failNext = false;
  int revision = 0, epoch = 0;
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
            total: 20,
          ),
    details: query.view == FeatureQueryView.bykcDetail
        ? const [FeatureDetail(title: '合成详情')]
        : [
            for (
              var i = ((query.page <= 0 ? 1 : query.page) - 1) * 10;
              i < (query.page <= 0 ? 1 : query.page) * 10;
              i++
            )
              FeatureDetail(
                title: '项目$i',
                presentation: BykcCoursePresentation(
                  id: i + 1,
                  courseName: '项目$i',
                  status: BykcCourseStatus.available,
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
  });
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
    snapshots: {
      for (final id in FeatureId.values)
        id: id == FeatureId.bykc ? snapshot : FeatureSnapshot(feature: id),
    },
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onFeatureQuery: read,
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  );
}
