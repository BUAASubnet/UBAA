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
}
