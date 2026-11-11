import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';

void main() {
  for (final fails in [false, true]) {
    testWidgets('选退课打断在途续载后保留前页且不显示续载错误，读取失败=$fails', (tester) async {
      final key = GlobalKey<FeatureReadNavigatorState>();
      final pending = Completer<void>();
      final requests = <int>[];
      Future<void> Function()? loadMore;
      final state = ValueNotifier(FeatureSnapshot(feature: FeatureId.bykc));
      addTearDown(state.dispose);
      String? moreError;
      var loading = false;
      var shown = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<FeatureSnapshot>(
            valueListenable: state,
            builder: (context, snapshot, _) => FeatureReadNavigator(
              key: key,
              snapshot: snapshot,
              cacheEpoch: 0,
              initialHomeTarget: const FeatureReadNavigation(
                feature: FeatureId.bykc,
                query: FeatureQuery(page: 1),
              ),
              onExit: () {},
              onRetry: () async {},
              onVisibleSnapshot: (_, __) {},
              pageBuilder: (page) {
                loadMore = page.onLoadMore;
                moreError = page.moreError;
                loading = page.loadingMore;
                shown = page.snapshot.details.map((d) => d.title).toList();
                return const SizedBox();
              },
              onQuery: (query) async {
                requests.add(query.page);
                if (query.page == 2) {
                  await pending.future;
                  if (fails) throw StateError('合成被打断的读取');
                }
                state.value = FeatureSnapshot(
                  feature: FeatureId.bykc,
                  status: FeatureLoadStatus.success,
                  readContext: FeatureReadContext(
                    query: query,
                    requestRevision: requests.length,
                  ),
                  pagination: FeaturePagination(
                    page: query.page,
                    size: 1,
                    total: 2,
                  ),
                  details: [
                    FeatureDetail(
                      title: '课程${query.page}',
                      presentation: BykcCoursePresentation(
                        id: query.page,
                        courseName: '课程${query.page}',
                        status: BykcCourseStatus.available,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, [1]);
      unawaited(loadMore!());
      await tester.pumpAndSettle();
      expect(requests, [1, 2]);
      expect(loading, isTrue);
      key.currentState!.beginBykcCourseWrite();
      pending.complete();
      await tester.pumpAndSettle();
      expect(shown, ['课程1']);
      expect(loading, isFalse);
      expect(moreError, isNull);
      expect(requests, [1, 2]);
    });
  }

  for (final stop in ['按需', '失败', '无新增', '写入', '离线', '隐藏']) {
    testWidgets('博雅按需续载遵守$stop条件且不自动追加后续页', (tester) async {
      final key = GlobalKey<FeatureReadNavigatorState>();
      final requests = <int>[];
      Future<void> Function()? loadMore;
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
                pageBuilder: (page) {
                  loadMore = page.onLoadMore;
                  return const SizedBox();
                },
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
      await tester.pumpAndSettle();
      expect(requests, [1]);
      await loadMore!();
      await tester.pumpAndSettle();
      expect(requests, ['按需', '失败', '无新增'].contains(stop) ? [1, 2] : [1]);
    });
  }
}
