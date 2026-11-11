import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/paged_results.dart';

FeatureSnapshot page(
  int number,
  List<int> ids, {
  ConnectionMode route = ConnectionMode.direct,
}) => FeatureSnapshot(
  feature: FeatureId.cgyy,
  status: FeatureLoadStatus.success,
  resolvedRoute: route,
  pagination: FeaturePagination(page: number, size: 2, total: 6),
  details: [
    for (final id in ids)
      FeatureDetail(
        title: '订单$id',
        presentation: CgyyOrderPresentation(id: id, statusText: '已取消'),
      ),
  ],
);

void main() {
  test('写入打断续载时保留前页且下一次仍请求原页', () {
    final feed = PagedResults();
    const query = FeatureQuery(view: FeatureQueryView.cgyyOrders);
    final first = page(1, [1, 2]);
    feed.accept(first, query);
    final next = feed.begin(first, query)!;
    feed.abandon();
    expect(feed.loading, isFalse);
    expect(feed.error, isNull);
    expect(feed.details.map((d) => d.title), ['订单1', '订单2']);
    expect(feed.begin(first, query)!.page, next.page);
    final merged = feed.accept(page(2, [3, 4]), next);
    expect(merged.details.map((d) => d.title), ['订单1', '订单2', '订单3', '订单4']);
  });

  test('同账号恢复读齐原页数后替换，失败和重复页保留旧列表', () {
    final feed = PagedResults();
    const query = FeatureQuery(view: FeatureQueryView.cgyyOrders);
    final first = page(1, [1, 2]);
    feed.accept(first, query);
    final second = feed.begin(first, query)!;
    feed.accept(page(2, [3, 4]), second);
    feed.cancelPending();
    feed.accept(page(2, [13, 14]), second);
    expect(feed.recoveryQuery!.page, 0);
    var shown = feed.accept(page(1, [11, 12]), feed.recoveryQuery);
    expect(shown.details.map((d) => d.title), ['订单1', '订单2', '订单3', '订单4']);
    expect(feed.recoveryQuery!.page, 1);
    shown = feed.accept(
      page(2, [13, 14]).copyWith(status: FeatureLoadStatus.failure),
      feed.recoveryQuery,
    );
    expect(shown.details.map((d) => d.title), ['订单1', '订单2', '订单3', '订单4']);
    expect(feed.recoveryQuery, isNull);
    expect(feed.begin(shown, second)!.page, 0);
    feed.accept(page(1, [11, 12]), feed.recoveryQuery);
    shown = feed.accept(page(2, [13, 14]), feed.recoveryQuery);
    expect(shown.details.map((d) => d.title), ['订单11', '订单12', '订单13', '订单14']);
    expect(feed.error, isNull);
    feed.cancelPending();
    feed.accept(page(2, [13, 14]), second);
    feed.accept(page(1, [11, 12]), feed.recoveryQuery);
    shown = feed.accept(page(1, [11, 12]), feed.recoveryQuery);
    expect(shown.details, hasLength(4));
    expect(feed.recoveryQuery, isNull);
    expect(feed.error, isNotNull);
  });

  test('零基请求续载去重，失败保留前页且重试原页', () {
    final feed = PagedResults();
    final first = page(1, [1, 2]);
    const query = FeatureQuery(view: FeatureQueryView.cgyyOrders);
    feed.accept(first, query);
    final next = feed.begin(first, query)!;
    expect(next.page, 1);
    expect(feed.begin(first, query), isNull);
    feed.fail();
    expect(feed.details.map((d) => d.title), ['订单1', '订单2']);
    expect(feed.begin(first, query)!.page, 1);
    final merged = feed.accept(page(2, [2, 3]), next);
    expect(merged.details.map((d) => d.title), ['订单1', '订单2', '订单3']);
    expect(feed.error, isNull);
    expect(merged.pagination!.total, 6);
    expect(merged.pagination!.page, 2);
  });
  test('路线变化或重复页不能并入原列表', () {
    final feed = PagedResults();
    const query = FeatureQuery(view: FeatureQueryView.cgyyOrders);
    final first = page(1, [1, 2]);
    feed.accept(first, query);
    final next = feed.begin(first, query)!;
    final merged = feed.accept(page(1, [1, 2]), next);
    expect(merged.details.length, 2);
    expect(feed.error, isNotNull);
    feed.reset();
    feed.accept(first, query);
    feed.begin(first, query);
    expect(
      feed.accept(page(2, [3], route: ConnectionMode.webvpn), next).details,
      isEmpty,
    );
    expect(feed.error, isNotNull);
  });
}
