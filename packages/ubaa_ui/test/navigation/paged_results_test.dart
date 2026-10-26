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
