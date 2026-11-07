import '../support/home_harness.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';

void main() {
  testWidgets('隐藏首页刷新遇到旧代周次在途取消时，继续读取新代周次', (tester) async {
    final key = GlobalKey<HomeViewState>();
    final gate = Completer<FeatureResult>();
    var epoch = 0, weekReads = 0;
    final forced = <bool>[];
    var visible = true;
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            key: key,
            user: null,
            visible: visible,
            cacheEpoch: epoch,
            snapshots: {
              for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
            },
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async => epoch++,
            onLoadSupplement: (source, force) async {
              if (source != HomeSupplement.currentWeek) {
                return const FeatureResult.empty();
              }
              forced.add(force);
              return ++weekReads == 1
                  ? gate.future
                  : const FeatureResult.empty();
            },
          ),
        ),
      ),
    );
    await mount();
    await tester.pump();
    visible = false;
    await mount();
    final refresh = key.currentState!.refresh();
    await mount();
    gate.complete(
      const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.operationConflict,
          title: '读取已取消',
          message: '合成旧代取消',
        ),
      ),
    );
    await tester.pump();
    await refresh;
    expect(weekReads, 2);
    expect(forced, [false, true]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('日程页刷新保活首页时强制重读当前周，不依赖首页可见', (tester) async {
    final key = GlobalKey<HomeViewState>();
    final calls = <(HomeSupplement, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            key: key,
            user: null,
            visible: false,
            cacheEpoch: 0,
            snapshots: {
              for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
            },
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onLoadSupplement: (source, force) async {
              calls.add((source, force));
              return const FeatureResult.empty();
            },
          ),
        ),
      ),
    );
    await key.currentState!.refresh();
    expect(calls, contains((HomeSupplement.currentWeek, true)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('读取代次变化保留在途补充来源且不会整轮重发', (tester) async {
    final gate = Completer<FeatureResult>();
    final calls = <HomeSupplement, int>{};
    Future<void> mount(int epoch) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            user: null,
            visible: true,
            cacheEpoch: epoch,
            snapshots: {
              for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
            },
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onLoadSupplement: (source, force) {
              calls.update(source, (v) => v + 1, ifAbsent: () => 1);
              return gate.future;
            },
          ),
        ),
      ),
    );
    await mount(0);
    await tester.pump();
    await mount(1);
    await tester.pump();
    gate.complete(const FeatureResult.empty());
    await tester.pumpAndSettle();
    expect(calls.keys, containsAll(HomeSupplement.values));
    expect(calls.values, everyElement(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('补充来源与快照变化不替代应用层的刷新完成信号', (tester) async {
    final key = GlobalKey<HomeViewState>();
    final supplements = Completer<FeatureResult>();
    final core = Completer<void>();
    var loading = false;
    var refining = false;
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            key: key,
            user: null,
            visible: true,
            cacheEpoch: 0,
            snapshots: {
              for (final f in FeatureId.values)
                f: FeatureSnapshot(
                  feature: f,
                  status: loading
                      ? FeatureLoadStatus.loading
                      : FeatureLoadStatus.empty,
                  refining: refining,
                ),
            },
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () => core.future,
            onSyncStatus: (_, _) {},
            onLoadSupplement: (_, _) => supplements.future,
          ),
        ),
      ),
    );
    await mount();
    await tester.pump();
    var done = false;
    final refresh = key.currentState!.refresh().then((_) => done = true);
    await tester.pump();
    await mount();
    supplements.complete(const FeatureResult.empty());
    await tester.pump();
    await tester.pump();
    expect(done, isFalse, reason: '主来源仍等待会话恢复');
    loading = true;
    await mount();
    refining = true;
    await mount();
    expect(done, isFalse, reason: 'UI 不根据快照推断应用层完成');
    core.complete();
    await refresh;
    expect(done, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('刷新等待已有补充读取完成且不重复发起', (tester) async {
    final gate = Completer<FeatureResult>();
    final key = GlobalKey<HomeViewState>();
    final calls = <HomeSupplement, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            key: key,
            user: null,
            visible: true,
            cacheEpoch: 0,
            snapshots: {
              for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
            },
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onLoadSupplement: (source, force) {
              calls.update(source, (v) => v + 1, ifAbsent: () => 1);
              return gate.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    var completed = false;
    final refresh = key.currentState!.refresh().then((_) => completed = true);
    await tester.pump();
    expect(completed, isFalse, reason: '在途的博雅与研讨室结果仍未到达');
    expect(calls.values, everyElement(1));
    gate.complete(const FeatureResult.empty());
    await refresh;
    await tester.pumpWidget(const SizedBox());
  });
}
