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

  test('服务端分页元数据按 1-based 页码计算总页数', () {
    const pagination = FeaturePagination(page: 2, size: 20, total: 41);
    expect(pagination.effectiveTotalPages, 3);
    const explicit = FeaturePagination(
      page: 1,
      size: 20,
      total: 41,
      totalPages: 5,
      hasMore: true,
    );
    expect(explicit.effectiveTotalPages, 5);
    expect(explicit.hasMore, isTrue);
  });

  test('typed action 保留目标、写操作与资格', () {
    const action = BykcSelectAction(
      courseId: 42,
      eligibility: ActionEligibility.allowed,
    );

    expect(action.courseId, 42);
    expect(action.operation, WriteOperation.bykcSelectCourse);
    expect(action.eligibility, ActionEligibility.allowed);
    const deselect = BykcDeselectAction(
      courseId: 9527,
      eligibility: ActionEligibility.allowed,
    );
    expect(deselect.courseId, 9527);
    expect(deselect.operation, WriteOperation.bykcDeselectCourse);
    expect(deselect.eligibility, ActionEligibility.allowed);
    expect(ActionEligibility.values, <ActionEligibility>[
      ActionEligibility.allowed,
      ActionEligibility.denied,
      ActionEligibility.unknown,
    ]);
  });

  test('博雅签到 action 固定映射协议类型并保留 typed 目标资格', () {
    const signIn = BykcSignAction(
      courseId: 9527,
      kind: BykcSignKind.signIn,
      eligibility: ActionEligibility.allowed,
      requiresCoordinates: false,
    );
    const signOut = BykcSignAction(
      courseId: 9527,
      kind: BykcSignKind.signOut,
      eligibility: ActionEligibility.unknown,
      requiresCoordinates: true,
    );

    expect(signIn.courseId, 9527);
    expect(signIn.kind, BykcSignKind.signIn);
    expect(signIn.signType, 1);
    expect(signIn.operation, WriteOperation.bykcSignCourse);
    expect(signIn.eligibility, ActionEligibility.allowed);
    expect(signIn.requiresCoordinates, isFalse);
    expect(signOut.courseId, 9527);
    expect(signOut.kind, BykcSignKind.signOut);
    expect(signOut.signType, 2);
    expect(signOut.operation, WriteOperation.bykcSignCourse);
    expect(signOut.eligibility, ActionEligibility.unknown);
    expect(signOut.requiresCoordinates, isTrue);
    expect(BykcSignKind.values, <BykcSignKind>[
      BykcSignKind.signIn,
      BykcSignKind.signOut,
    ]);
  });

  test('详情可按类型稳定查找 action，缺失时默认为空', () {
    const action = BykcSelectAction(
      courseId: 42,
      eligibility: ActionEligibility.denied,
    );
    const detail = FeatureDetail(title: '课程', actions: <FeatureAction>[action]);
    const detailWithoutActions = FeatureDetail(title: '无写入能力的详情');

    expect(detail.action<BykcSelectAction>(), same(action));
    expect(detail.action<FeatureAction>(), same(action));
    expect(detailWithoutActions.actions, isEmpty);
    expect(detailWithoutActions.action<BykcSelectAction>(), isNull);
  });
}
