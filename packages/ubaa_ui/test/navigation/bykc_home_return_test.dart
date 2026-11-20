import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';

void main() {
  testWidgets('首页直达博雅课程详情返回后，功能入口打开选课列表而不是详情', (tester) async {
    final key = GlobalKey<FeatureReadNavigatorState>();
    final snapshot = ValueNotifier(FeatureSnapshot(feature: FeatureId.bykc));
    addTearDown(snapshot.dispose);
    final queries = <FeatureQuery>[];
    var exits = 0;
    Future<void> read(FeatureQuery query) async {
      queries.add(query);
      final detail = query.view == FeatureQueryView.bykcDetail;
      snapshot.value = FeatureSnapshot(
        feature: FeatureId.bykc,
        status: FeatureLoadStatus.success,
        resolvedRoute: ConnectionMode.direct,
        readContext: FeatureReadContext(
          query: query,
          requestRevision: queries.length,
        ),
        details: [FeatureDetail(title: detail ? '详情课程' : '列表课程')],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<FeatureSnapshot>(
          valueListenable: snapshot,
          builder: (_, value, _) => FeatureReadNavigator(
            key: key,
            snapshot: value,
            cacheEpoch: 0,
            initialHomeTarget: const FeatureReadNavigation(
              feature: FeatureId.bykc,
              query: FeatureQuery(
                view: FeatureQueryView.bykcDetail,
                courseId: '7',
              ),
            ),
            onExit: () => exits++,
            onRetry: () async {},
            onVisibleSnapshot: (_, _) {},
            onQuery: read,
            pageBuilder: (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      key.currentState!.currentFrame.query?.view,
      FeatureQueryView.bykcDetail,
    );
    key.currentState!.goBack();
    await tester.pump();
    expect(exits, 1, reason: '首页直达的详情返回首页');

    key.currentState!.openList();
    await tester.pumpAndSettle();
    final frame = key.currentState!.currentFrame;
    expect(frame.query?.view, FeatureQueryView.summary);
    expect(queries.last.view, FeatureQueryView.summary);
    expect(frame.snapshot.details.map((d) => d.title), ['列表课程']);
    key.currentState!.goBack();
    await tester.pump();
    expect(exits, 2, reason: '列表第一层返回退出功能');
  });
}
