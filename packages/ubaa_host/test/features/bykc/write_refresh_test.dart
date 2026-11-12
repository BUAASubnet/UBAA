import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import 'package:ubaa_test_support/navigation.dart';

void main() {
  for (final failRefresh in [false, true]) {
    testWidgets('选课成功后刷新列表，网络失败=$failRefresh', (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = await support.widgetAccounts(tester);
      final backend = _Backend()..failRefresh = failRefresh;
      await tester.pumpWidget(
        UbaaAppHost(backend: backend, localAccountStore: accounts),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      await openFeature(tester, FeatureId.bykc);
      await tester.tap(find.widgetWithText(FilledButton, '选课').first);
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(backend.commits, 1);
      expect(backend.readbacks, 1);
      expect(backend.postWriteLists, greaterThan(0));
      final page = tester.state<FeatureReadNavigatorState>(
        find.byType(FeatureReadNavigator),
      );
      final snapshot = page.currentFrame.snapshot;
      if (failRefresh) {
        expect(find.text('选课成功，列表暂未更新'), findsOneWidget);
        expect(snapshot.error?.code, UbaaErrorCode.networkError);
        expect(snapshot.details.single.actions, isEmpty);
      } else {
        expect(find.text('选课成功'), findsOneWidget);
        expect(snapshot.error, isNull);
        expect(
          (snapshot.details.single.presentation! as BykcCoursePresentation)
              .selected,
          isTrue,
        );
      }
      expect(page.currentFrame.query!.view, FeatureQueryView.summary);
      await tester.pump(const Duration(seconds: 3));
      expect(backend.commits, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Backend extends support.FakeRecoveryBackend
    implements
        FeatureQueryBackend,
        ProgressiveReadBackend,
        BykcWriteBackend,
        CacheWriteBackend,
        PinnedWriteReadbackBackend,
        OfflineQueryBackend {
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const OfflineQueryRead(null);
  }

  bool failRefresh = false;
  int commits = 0, readbacks = 0, postWriteLists = 0;
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      feature == FeatureId.bykc
      ? loadFeatureQuery(feature, const FeatureQuery(page: 1))
      : super.loadFeature(feature);
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (feature != FeatureId.bykc || query.view != FeatureQueryView.summary) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    if (commits > 0) {
      postWriteLists++;
      if (failRefresh) throw const BackendException(UbaaErrorCode.networkError);
    }
    return FeatureResult.success(
      resolvedRoute: ConnectionMode.direct,
      pagination: FeaturePagination(
        page: query.page <= 0 ? 1 : query.page,
        size: 20,
        total: 1,
      ),
      details: [
        FeatureDetail(
          title: '合成课程',
          presentation: BykcCoursePresentation(
            id: 42,
            courseName: '合成课程',
            status: commits == 0
                ? BykcCourseStatus.available
                : BykcCourseStatus.selected,
            selected: commits > 0,
          ),
          actions: commits == 0
              ? const [
                  BykcSelectAction(
                    courseId: 42,
                    eligibility: ActionEligibility.allowed,
                  ),
                ]
              : const [],
        ),
      ],
    );
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      WriteIntent(
        intentId: 'synthetic',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '合成课程',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'synthetic',
      );
  @override
  Future<WriteIntent> prepareBykcDeselectCourse({
    required int courseId,
  }) async => throw UnimplementedError();
  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async => throw UnimplementedError();
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    return const WriteCommitResult(
      operation: WriteOperation.bykcSelectCourse,
      success: true,
      outcomeUnknown: false,
      message: '选课成功',
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => commitWrite(intentId);
  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) async {
    readbacks++;
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
}
