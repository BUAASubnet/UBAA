import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 生成 API 的轻量 schema 快照。
///
/// 该测试不读取真实数据，只固定公开方法、DTO 和枚举的最小集合；完整字节漂移仍由
/// `just flutter-codegen-check` 负责。这样生成器意外删除一个业务入口时，Dart 门禁会先失败。
void main() {
  final client = File('lib/src/rust/api/client.dart').readAsStringSync();
  final read = File('lib/src/rust/api/read.dart').readAsStringSync();
  final write = File('lib/src/rust/api/write.dart').readAsStringSync();

  test('BridgeClient 暴露认证、路线、全部读取和写入入口', () {
    const methods = <String>[
      'authStatus',
      'prepareLogin',
      'login',
      'userInfo',
      'logout',
      'routeSettings',
      'setDefaultRoutePolicy',
      'scheduleTerms',
      'scheduleWeeks',
      'scheduleWeek',
      'scheduleToday',
      'examArrangement',
      'grades',
      'classroomSearch',
      'signinToday',
      'spocAssignments',
      'spocAssignment',
      'judgeAssignments',
      'judgeAssignment',
      'judgeAssignmentDetails',
      'bykcProfile',
      'bykcCourses',
      'bykcCourseDetail',
      'bykcChosenCourses',
      'bykcStatistics',
      'libbookLibraries',
      'libbookAreas',
      'libbookAreaDetail',
      'libbookSeats',
      'libbookBookings',
      'ygdkOverview',
      'ygdkRecords',
      'cgyySites',
      'cgyyPurposeTypes',
      'cgyyDayInfo',
      'cgyyOrders',
      'cgyyOrderDetail',
      'cgyyLockCode',
      'evaluationAll',
      'prepareBykcSelectCourse',
      'prepareBykcDeselectCourse',
      'prepareBykcSignCourse',
      'prepareSigninPerform',
      'prepareLibbookReserve',
      'prepareLibbookCancelBooking',
      'prepareYgdkSubmit',
      'prepareCgyySubmitReservation',
      'prepareCgyyCancelOrder',
      'prepareEvaluationSubmitCourses',
      'commitWrite',
    ];
    for (final method in methods) {
      expect(
        client,
        contains(RegExp(r'\b' + method + r'\s*\(')),
        reason: '生成 API 缺少 $method',
      );
    }
    expect(client, isNot(contains('evaluationPending')));
    expect(client, isNot(contains('evaluation_pending')));
  });

  test('生成 DTO 快照保留领域白名单和安全来源字段', () {
    const dtoNames = <String>[
      'BridgeRoutedTerms',
      'BridgeRoutedWeeklySchedule',
      'BridgeRoutedTodayClasses',
      'BridgeRoutedExamArrangement',
      'BridgeRoutedGrades',
      'BridgeRoutedClassroomQuery',
      'BridgeRoutedSigninClasses',
      'BridgeRoutedSpocAssignments',
      'BridgeRoutedJudgeSummaries',
      'BridgeRoutedBykcCourses',
      'BridgeRoutedLibBookLibraries',
      'BridgeRoutedYgdkRecords',
      'BridgeRoutedCgyySites',
      'BridgeRoutedEvaluation',
      'BridgeCgyyLockCode',
    ];
    for (final name in dtoNames) {
      expect(read, contains('class $name'), reason: '生成 DTO 缺少 $name');
    }
    expect(read, contains('enum BridgeCgyyPurposeSource'));
    expect(read, contains('staticFallback'));
    expect(read, contains('available'));
  });

  test('生成 DTO 快照覆盖全部公开读取类型', () {
    const allDtoNames = <String>[
      'BridgeBykcChosenCourse',
      'BridgeBykcCourse',
      'BridgeBykcCoursePage',
      'BridgeBykcSignConfig',
      'BridgeBykcSignPoint',
      'BridgeBykcStatistic',
      'BridgeBykcStatistics',
      'BridgeBykcUserProfile',
      'BridgeCgyyDayInfo',
      'BridgeCgyyLockCode',
      'BridgeCgyyOrder',
      'BridgeCgyyOrdersPage',
      'BridgeCgyyPurposeType',
      'BridgeCgyyPurposeTypes',
      'BridgeCgyySlotStatus',
      'BridgeCgyySpaceAvailability',
      'BridgeCgyyTimeSlot',
      'BridgeCgyyVenueSite',
      'BridgeClassroomFloor',
      'BridgeClassroomInfo',
      'BridgeClassroomQuery',
      'BridgeCourseClass',
      'BridgeEvaluationCourse',
      'BridgeEvaluationCoursesResponse',
      'BridgeEvaluationProgress',
      'BridgeExam',
      'BridgeExamArrangement',
      'BridgeGrade',
      'BridgeGradeData',
      'BridgeJudgeAssignmentDetail',
      'BridgeJudgeAssignmentKey',
      'BridgeJudgeAssignmentSummary',
      'BridgeJudgeProblem',
      'BridgeLibBookArea',
      'BridgeLibBookAreaDetail',
      'BridgeLibBookBooking',
      'BridgeLibBookBookingsPage',
      'BridgeLibBookLibrary',
      'BridgeLibBookSeat',
      'BridgeLibBookStorey',
      'BridgeLibBookTimeSlot',
      'BridgeRoutedBykcChosenCourses',
      'BridgeRoutedBykcCourse',
      'BridgeRoutedBykcCourses',
      'BridgeRoutedBykcProfile',
      'BridgeRoutedBykcStatistics',
      'BridgeRoutedCgyyDayInfo',
      'BridgeRoutedCgyyLockCode',
      'BridgeRoutedCgyyOrder',
      'BridgeRoutedCgyyOrders',
      'BridgeRoutedCgyyPurposeTypes',
      'BridgeRoutedCgyySites',
      'BridgeRoutedClassroomQuery',
      'BridgeRoutedEvaluation',
      'BridgeRoutedExamArrangement',
      'BridgeRoutedGrades',
      'BridgeRoutedJudgeAssignmentDetail',
      'BridgeRoutedJudgeAssignmentDetails',
      'BridgeRoutedJudgeSummaries',
      'BridgeRoutedLibBookAreaDetail',
      'BridgeRoutedLibBookAreas',
      'BridgeRoutedLibBookBookings',
      'BridgeRoutedLibBookLibraries',
      'BridgeRoutedLibBookSeats',
      'BridgeRoutedSigninClasses',
      'BridgeRoutedSpocAssignmentDetail',
      'BridgeRoutedSpocAssignments',
      'BridgeRoutedTerms',
      'BridgeRoutedTodayClasses',
      'BridgeRoutedWeeklySchedule',
      'BridgeRoutedWeeks',
      'BridgeRoutedYgdkOverview',
      'BridgeRoutedYgdkRecords',
      'BridgeSigninClass',
      'BridgeSpocAssignmentDetail',
      'BridgeSpocAssignmentSummary',
      'BridgeSpocAssignments',
      'BridgeTerm',
      'BridgeTodayClass',
      'BridgeWeek',
      'BridgeWeeklySchedule',
      'BridgeYgdkItem',
      'BridgeYgdkOverview',
      'BridgeYgdkRecord',
      'BridgeYgdkRecordsPage',
      'BridgeYgdkTermSummary',
    ];
    for (final name in allDtoNames) {
      expect(read, contains('class $name'), reason: '生成 DTO 缺少 $name');
    }
  });

  test('场馆订单 DTO 不跨 FFI 暴露敏感订单字段', () {
    final match = RegExp(
      r'class BridgeCgyyOrder \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(match, isNotNull);
    final body = match!.namedGroup('body')!;
    for (final forbidden in <String>[
      'tradeNo',
      'phone',
      'payStatus',
      'activityContent',
      'joiners',
      'checkContent',
      'handleReason',
      'remark',
    ]) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason: 'BridgeCgyyOrder 不得暴露 $forbidden',
      );
    }
  });

  test('场馆时段与博雅已选课程 DTO 不暴露内部材料', () {
    final chosen = RegExp(
      r'class BridgeBykcChosenCourse \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(chosen, isNotNull);
    final chosenBody = chosen!.namedGroup('body')!;
    for (final forbidden in <String>[
      'homework',
      'homeworkAttachmentName',
      'homeworkAttachmentPath',
      'signInfo',
    ]) {
      expect(
        chosenBody,
        isNot(contains(forbidden)),
        reason: 'BridgeBykcChosenCourse 不得暴露 $forbidden',
      );
    }

    final slot = RegExp(
      r'class BridgeCgyySlotStatus \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(slot, isNotNull);
    final slotBody = slot!.namedGroup('body')!;
    for (final forbidden in <String>[
      'tradeNo',
      'orderId',
      'useNum',
      'alreadyNum',
      'takeUp',
      'takeUpExplain',
    ]) {
      expect(
        slotBody,
        isNot(contains(forbidden)),
        reason: 'BridgeCgyySlotStatus 不得暴露 $forbidden',
      );
    }
  });

  test('阳光打卡记录 DTO 不暴露图片地址', () {
    final record = RegExp(
      r'class BridgeYgdkRecord \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(record, isNotNull);
    final body = record!.namedGroup('body')!;
    expect(
      body,
      isNot(contains('images')),
      reason: 'BridgeYgdkRecord 不得暴露图片地址列表',
    );
    expect(body, contains('imageCount'));
  });

  test('写入 schema 仍是十项封闭 operation 和一次性 intent', () {
    const operations = <String>[
      'bykcSelectCourse',
      'bykcDeselectCourse',
      'bykcSignCourse',
      'signinPerform',
      'libbookReserve',
      'libbookCancelBooking',
      'ygdkSubmit',
      'cgyySubmitReservation',
      'cgyyCancelOrder',
      'evaluationSubmitCourses',
    ];
    for (final operation in operations) {
      expect(write, contains(operation));
    }
    expect(write, contains('class BridgeWriteIntent'));
    expect(write, contains('requestDigest'));
    expect(write, contains('expiresAt'));
  });
}
