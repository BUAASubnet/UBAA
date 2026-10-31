import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';

void main() {
  testWidgets('读取代次变化保留在途补充来源且不会整轮重发', (tester) async {
    final gate = Completer<FeatureResult>();
    final calls = <HomeSupplement, int>{};
    Future<void> mount(int epoch) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
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
  testWidgets('补充来源结束不能提前完成尚未开始发布的主来源，首批结果后结束下拉', (tester) async {
    final key = GlobalKey<HomeViewState>();
    final supplements = Completer<FeatureResult>();
    final core = Completer<void>();
    var loading = false;
    var refining = false;
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
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
    await refresh;
    expect(done, isTrue);
    expect(core.isCompleted, isFalse, reason: '后台补全不阻塞下拉');
    core.complete();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('刷新等待已有补充读取完成且不重复发起', (tester) async {
    final gate = Completer<FeatureResult>();
    final key = GlobalKey<HomeViewState>();
    final calls = <HomeSupplement, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
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
