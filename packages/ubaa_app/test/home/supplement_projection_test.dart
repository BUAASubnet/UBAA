import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/home/agenda.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  for (final feature in [FeatureId.bykc, FeatureId.cgyy]) {
    for (final cached in [false, true]) {
      test('${feature.name} 在线更新保留待办来源，失败保留内容，空结果清除旧项，缓存=$cached', () async {
        final now = DateTime.parse('2026-11-13T13:24:00Z');
        final view = feature == FeatureId.bykc
            ? FeatureQueryView.bykcChosenCourses
            : FeatureQueryView.cgyyOrders;
        final detail = feature == FeatureId.bykc
            ? const FeatureDetail(
                title: '合成博雅课程',
                presentation: BykcChosenPresentation(
                  recordId: 1,
                  courseId: 2,
                  courseName: '合成博雅课程',
                  courseStartDate: '2026-11-19 14:30:00',
                  courseEndDate: '2026-11-19 16:00:00',
                ),
              )
            : const FeatureDetail(
                title: '合成场馆预约',
                presentation: CgyyOrderPresentation(
                  id: 3,
                  statusText: '预约成功',
                  reservationStartDate: '2026-11-19 14:30:00',
                  reservationEndDate: '2026-11-19 16:00:00',
                ),
              );
        var response = FeatureResult.success(details: [detail]);
        var projectedIds = <int>[];
        final model = HomeCoordinator(
          now: () => now,
          loadSupplement: (_, _) async => response,
          loadDay: (_, _) async => const FeatureResult.empty(),
          project: (request) async {
            final input = bridgeHomeAgendaInputs(request);
            projectedIds = feature == FeatureId.bykc
                ? input.bykc.map((item) => item.courseId).toList()
                : input.cgyy.map((item) => item.orderId).toList();
            return HomeTodoProjection(const []);
          },
          refreshMain: () async {},
          retryMain: (_) async {},
          changed: () {},
        );
        addTearDown(model.dispose);
        model.update(
          owner: 'synthetic',
          snapshots: {
            if (cached)
              feature: FeatureSnapshot(
                feature: feature,
                status: FeatureLoadStatus.stale,
                details: [detail],
                updatedAt: now,
                readContext: FeatureReadContext(
                  query: FeatureQuery(view: view),
                  requestRevision: 0,
                ),
              ),
          },
          epoch: 0,
          agenda: 0,
          active: true,
          online: false,
          blocked: false,
          foreground: false,
          readDays: false,
        );
        final expectedIds = [feature == FeatureId.bykc ? 2 : 3];
        await model.flushProjection();
        expect(projectedIds, cached ? expectedIds : isEmpty);

        await model.retry(feature);
        await model.flushProjection();
        expect(projectedIds, expectedIds);

        response = const FeatureResult.failure(
          UiError(
            code: UbaaErrorCode.networkError,
            title: '连接失败',
            message: '合成网络错误',
            retryable: true,
          ),
        );
        await model.retry(feature);
        await model.flushProjection();
        expect(projectedIds, expectedIds);

        response = const FeatureResult.empty();
        await model.retry(feature);
        await model.flushProjection();
        expect(projectedIds, isEmpty);
      });
    }
  }
}
