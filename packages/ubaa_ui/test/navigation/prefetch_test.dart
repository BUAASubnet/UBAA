import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';

void main() {
  for (final stop in ['上限', '失败', '无新增', '写入', '离线', '隐藏']) {
    testWidgets('博雅预取在$stop时停止且不会自动重试', (tester) async {
      final key = GlobalKey<FeatureReadNavigatorState>();
      final requests = <int>[];
      final state = ValueNotifier(FeatureSnapshot(feature: FeatureId.bykc));
      addTearDown(state.dispose);
      const epoch = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<FeatureSnapshot>(
            valueListenable: state,
            builder: (context, snapshot, _) => TickerMode(
              enabled: stop != '隐藏',
              child: FeatureReadNavigator(
                key: key,
                snapshot: snapshot,
                cacheEpoch: epoch,
                initialHomeTarget: const FeatureReadNavigation(
                  feature: FeatureId.bykc,
                  query: FeatureQuery(page: 1),
                ),
                onExit: () {
                  state.value = FeatureSnapshot(feature: FeatureId.bykc);
                },
                onRetry: () async {},
                onVisibleSnapshot: (_, _) {},
                pageBuilder: (_) => const SizedBox(),
                onQuery: (query) async {
                  requests.add(query.page);
                  state.value = FeatureSnapshot(
                    feature: FeatureId.bykc,
                    status: stop == '失败' && query.page == 2
                        ? FeatureLoadStatus.failure
                        : FeatureLoadStatus.success,
                    readContext: FeatureReadContext(
                      query: query,
                      requestRevision: requests.length,
                    ),
                    evidence: stop == '离线'
                        ? DataEvidence(
                            accountId: 'synthetic',
                            origin: DataOrigin.persisted,
                            fetchedAt: DateTime(2026),
                            complete: true,
                            savedForOffline: true,
                          )
                        : null,
                    pagination: FeaturePagination(
                      page: query.page,
                      size: 8,
                      total: 80,
                    ),
                    details: [
                      for (var i = 0; i < 8; i++)
                        FeatureDetail(
                          title: '课程${query.page}-$i',
                          presentation: BykcCoursePresentation(
                            id: (stop == '无新增' ? 0 : query.page * 8) + i,
                            courseName: '课程$i',
                            status: BykcCourseStatus.available,
                          ),
                        ),
                    ],
                  );
                  if (requests.length == 1 && stop == '写入') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      key.currentState!.beginBykcCourseWrite();
                    });
                  }
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump();
      }
      expect(
        requests,
        stop == '上限'
            ? [1, 2, 3, 4, 5]
            : ['失败', '无新增'].contains(stop)
            ? [1, 2]
            : [1],
      );
    });
  }
}
