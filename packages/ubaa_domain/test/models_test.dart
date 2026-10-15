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
      <String>['课堂签到', '研讨室预约', '阳光打卡', '教学评教'],
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

  test('博雅选退课映射写操作且资格保持三态', () {
    const action = BykcSelectAction(
      courseId: 42,
      eligibility: ActionEligibility.allowed,
    );

    expect(action.operation, WriteOperation.bykcSelectCourse);
    const deselect = BykcDeselectAction(
      courseId: 9527,
      eligibility: ActionEligibility.allowed,
    );
    expect(deselect.operation, WriteOperation.bykcDeselectCourse);
    expect(ActionEligibility.values, <ActionEligibility>[
      ActionEligibility.allowed,
      ActionEligibility.denied,
      ActionEligibility.unknown,
    ]);
  });

  test('博雅签到签退映射固定协议类型与写操作', () {
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

    expect(signIn.signType, 1);
    expect(signIn.operation, WriteOperation.bykcSignCourse);
    expect(signOut.signType, 2);
    expect(signOut.operation, WriteOperation.bykcSignCourse);
    expect(BykcSignKind.values, <BykcSignKind>[
      BykcSignKind.signIn,
      BykcSignKind.signOut,
    ]);
  });

  test('基本写动作映射到正确操作', () {
    const cases = <FeatureAction, WriteOperation>{
      SigninPerformAction(
        scheduleId: 'schedule-safe',
        eligibility: ActionEligibility.allowed,
      ): WriteOperation.signinPerform,
      LibbookReserveAction(
        areaId: 'area-safe',
        seatId: 'seat-safe',
        day: '2026-09-04',
        segment: 'segment-safe',
        startTime: '08:00',
        endTime: '10:00',
        eligibility: ActionEligibility.allowed,
      ): WriteOperation.libbookReserve,
      LibbookCancelAction(
        bookingId: 'booking-safe',
        page: 2,
        limit: 20,
        eligibility: ActionEligibility.allowed,
      ): WriteOperation.libbookCancelBooking,
      CgyyReserveAction(
        venueSiteId: 3,
        reservationDate: '2026-09-04',
        spaceId: 4,
        timeId: 900,
        venueSpaceGroupId: 9,
        timeOrdinal: 0,
        eligibility: ActionEligibility.allowed,
      ): WriteOperation.cgyySubmitReservation,
    };
    for (final entry in cases.entries) {
      expect(entry.key.operation, entry.value);
    }
  });

  test('场馆取消 action 只保留 Core 核对的 typed 目标与三态资格', () {
    const action = CgyyCancelAction(
      orderId: 17,
      orderStatus: 1,
      checkStatus: 2,
      targetOrderId: 17,
      eligibility: ActionEligibility.allowed,
    );
    const denied = CgyyCancelAction(
      orderId: 17,
      orderStatus: 2,
      checkStatus: 2,
      targetOrderId: null,
      eligibility: ActionEligibility.denied,
    );
    const cancelled = CgyyCancelAction(
      orderId: 17,
      orderStatus: 2,
      checkStatus: 2,
      targetOrderId: null,
      cancelledTargetOrderId: 17,
      eligibility: ActionEligibility.denied,
    );

    expect(action.operation, WriteOperation.cgyyCancelOrder);
    expect(action.hasCanonicalTarget, isTrue);
    expect(denied.hasCanonicalTarget, isFalse);
    expect(cancelled.confirmsCancellationOf(17), isTrue);
    expect(cancelled.confirmsCancellationOf(18), isFalse);
    expect(denied.confirmsCancellationOf(17), isFalse);
    expect(
      const CgyyCancelAction(
        orderId: 17,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 18,
        eligibility: ActionEligibility.allowed,
      ).hasCanonicalTarget,
      isFalse,
    );
    expect(
      const CgyyCancelAction(
        orderId: 0,
        orderStatus: 1,
        checkStatus: 2,
        targetOrderId: 0,
        eligibility: ActionEligibility.allowed,
      ).hasCanonicalTarget,
      isFalse,
    );
  });

  test('阳光打卡 action 只有在资格允许且分类与项目目标完整时可用', () {
    const allowed = YgdkSubmitAction(
      classifyId: 31,
      itemId: 7,
      eligibility: ActionEligibility.allowed,
    );
    const unknown = YgdkSubmitAction(
      classifyId: 31,
      itemId: 7,
      eligibility: ActionEligibility.unknown,
    );
    const incomplete = YgdkSubmitAction(
      classifyId: 0,
      itemId: 7,
      eligibility: ActionEligibility.allowed,
    );

    expect(allowed.operation, WriteOperation.ygdkSubmit);
    expect(allowed.hasCanonicalTarget, isTrue);
    expect(unknown.hasCanonicalTarget, isFalse);
    expect(incomplete.hasCanonicalTarget, isFalse);
  });

  test('评教 action 只允许 Core 给出的完整 typed 目标且 selection key 覆盖教师', () {
    const target = EvaluationSubmitTarget(
      rwid: 'task|safe',
      wjid: 'questionnaire:safe',
      kcdm: 'course-safe',
      bpdm: 'teacher-safe',
    );
    const sameTarget = EvaluationSubmitTarget(
      rwid: 'task|safe',
      wjid: 'questionnaire:safe',
      kcdm: 'course-safe',
      bpdm: 'teacher-safe',
    );
    const otherTeacher = EvaluationSubmitTarget(
      rwid: 'task|safe',
      wjid: 'questionnaire:safe',
      kcdm: 'course-safe',
      bpdm: 'teacher-other',
    );
    const shiftedSeparator = EvaluationSubmitTarget(
      rwid: 'task',
      wjid: 'safe|questionnaire:safe',
      kcdm: 'course-safe',
      bpdm: 'teacher-safe',
    );
    const emptyTeacher = EvaluationSubmitTarget(
      rwid: 'task|safe',
      wjid: 'questionnaire:safe',
      kcdm: 'course-safe',
      bpdm: '',
    );
    const missingTeacher = EvaluationSubmitTarget(
      rwid: 'task|safe',
      wjid: 'questionnaire:safe',
      kcdm: 'course-safe',
    );

    expect(target.selectionKey, sameTarget.selectionKey);
    expect(target.selectionKey, isNot(otherTeacher.selectionKey));
    expect(target.selectionKey, isNot(shiftedSeparator.selectionKey));
    expect(emptyTeacher.selectionKey, missingTeacher.selectionKey);
    expect(target.hasRequiredIdentity, isTrue);
    expect(
      const EvaluationSubmitTarget(
        rwid: ' ',
        wjid: 'questionnaire-safe',
        kcdm: 'course-safe',
      ).hasRequiredIdentity,
      isFalse,
    );

    const allowed = EvaluationSubmitAction(
      eligibility: ActionEligibility.allowed,
      target: target,
    );
    const denied = EvaluationSubmitAction(
      eligibility: ActionEligibility.denied,
      target: target,
    );
    const unknown = EvaluationSubmitAction(
      eligibility: ActionEligibility.unknown,
      target: target,
    );
    const missing = EvaluationSubmitAction(
      eligibility: ActionEligibility.allowed,
      target: null,
    );

    expect(allowed.operation, WriteOperation.evaluationSubmitCourses);
    expect(allowed.hasCanonicalTarget, isTrue);
    expect(denied.hasCanonicalTarget, isFalse);
    expect(unknown.hasCanonicalTarget, isFalse);
    expect(missing.hasCanonicalTarget, isFalse);
  });

  test('评教结果保留成功、失败、未知和未尝试四态', () {
    expect(EvaluationCourseOutcome.values, <EvaluationCourseOutcome>[
      EvaluationCourseOutcome.success,
      EvaluationCourseOutcome.failure,
      EvaluationCourseOutcome.outcomeUnknown,
      EvaluationCourseOutcome.unattempted,
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
