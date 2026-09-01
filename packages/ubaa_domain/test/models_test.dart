import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('普通功能顺序与旧版一致', () {
    expect(
      ordinaryFeatureIds.map((feature) => feature.title).toList(),
      <String>[
        '课表查询',
        '考试查询',
        '成绩查询',
        '博雅课程',
        '空教室查询',
        'SPOC作业',
        '希冀作业',
        '图书馆座位',
      ],
    );
    expect(
      advancedFeatureIds.map((feature) => feature.title).toList(),
      <String>['课堂签到', '场馆预约', '阳光打卡', '教学评教'],
    );
  });

  test('路线策略使用稳定 wire 名称', () {
    expect(RoutePolicy.auto.wireName, 'auto');
    expect(RoutePolicy.direct.wireName, 'direct');
    expect(RoutePolicy.webvpn.wireName, 'webvpn');
  });

  test('领域查询参数保留学期、周次、校区和分页边界', () {
    const query = FeatureQuery(
      term: '2026-2027-1',
      week: 3,
      campus: 2,
      page: 1,
      size: 50,
      view: FeatureQueryView.bykcDetail,
      courseId: '12345',
    );
    final copied = query.copyWith(size: 20);
    expect(copied.term, '2026-2027-1');
    expect(copied.week, 3);
    expect(copied.campus, 2);
    expect(copied.page, 1);
    expect(copied.size, 20);
    expect(copied.view, FeatureQueryView.bykcDetail);
    expect(copied.courseId, '12345');
  });
}
