import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/schedule/flow.dart';

void main() {
  for (final boundary in ['账号或路线变化', '离开课表']) {
    testWidgets('学期弹窗期间$boundary不应用迟到选择', (tester) async {
      final key = GlobalKey<ScheduleFlowState>();
      final queries = <FeatureQuery>[];
      var epoch = 0;
      var visible = true;
      late StateSetter update;
      const query = FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: '原学期',
        week: 3,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                appBar: AppBar(
                  actions: [
                    IconButton(
                      tooltip: '选择学期',
                      onPressed: () => key.currentState?.selectTerm(),
                      icon: const Icon(Icons.calendar_month),
                    ),
                  ],
                ),
                body: ScheduleFlow(
                  key: key,
                  query: query,
                  visible: visible,
                  epoch: epoch,
                  snapshot: FeatureSnapshot(
                    feature: FeatureId.schedule,
                    status: FeatureLoadStatus.empty,
                    readContext: FeatureReadContext(
                      query: query,
                      requestRevision: 1,
                    ),
                  ),
                  loadWeeks: (_, _) async => const FeatureResult.empty(),
                  loadTerms: (_) async => const FeatureResult.success(
                    details: [
                      FeatureDetail(
                        title: '新学期',
                        presentation: TermPresentation(
                          code: 'next-term',
                          selected: false,
                          index: 1,
                        ),
                      ),
                    ],
                  ),
                  onQuery: (value) async {
                    queries.add(value);
                  },
                  child: const SizedBox(),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('选择学期'));
      await tester.pumpAndSettle();
      update(() {
        if (boundary == '离开课表') {
          visible = false;
        } else {
          epoch++;
        }
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('新学期'));
      await tester.pumpAndSettle();
      expect(queries, isEmpty);
    });
  }

  testWidgets('隐藏页不下载，进入后每学期一次，切周与重建不重复', (tester) async {
    var visible = false;
    var epoch = 0;
    var query = const FeatureQuery(
      view: FeatureQueryView.scheduleWeeks,
      term: '本学期',
    );
    final starts = <String>[];
    Future<void> render() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleFlow(
              snapshot: FeatureSnapshot(
                feature: FeatureId.schedule,
                status: FeatureLoadStatus.empty,
                resolvedRoute: ConnectionMode.direct,
                readContext: FeatureReadContext(
                  query: query,
                  requestRevision: 1,
                ),
              ),
              query: query,
              visible: visible,
              epoch: epoch,
              loadWeeks: (_, _) async => const FeatureResult.empty(),
              onQuery: (_) async {},
              onSave: (term) async {
                starts.add(term);
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render();
    expect(starts, isEmpty);
    visible = true;
    await render();
    expect(starts, ['本学期']);
    query = const FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: '本学期',
      week: 3,
    );
    await render();
    visible = false;
    await render();
    visible = true;
    await render();
    expect(starts, ['本学期']);
    query = const FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: '另一学期',
      week: 2,
    );
    await render();
    expect(starts, ['本学期', '另一学期']);
    epoch++;
    await render();
    expect(starts, ['本学期', '另一学期', '另一学期']);
  });

  for (final status in ScheduleImportStatus.values) {
    testWidgets('已有$status任务不会因重新进入课表自动重试', (tester) async {
      var starts = 0;
      const query = FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: '本学期',
        week: 3,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleFlow(
              snapshot: FeatureSnapshot(
                feature: FeatureId.schedule,
                status: FeatureLoadStatus.empty,
                resolvedRoute: ConnectionMode.direct,
                readContext: FeatureReadContext(
                  query: query,
                  requestRevision: 1,
                ),
              ),
              query: query,
              visible: true,
              epoch: 0,
              loadWeeks: (_, _) async => const FeatureResult.empty(),
              onQuery: (_) async {},
              imports: {'本学期': ScheduleImportState(status: status)},
              onSave: (_) async {
                starts++;
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(starts, 0);
    });
  }
}
