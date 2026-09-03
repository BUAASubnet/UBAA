import 'package:meta/meta.dart';

/// 领域详情读取的稳定视图。默认 [summary] 保持首页摘要行为；其余值只对
/// 对应领域生效，bridge 会拒绝缺少必要 ID 或时段的查询。
enum FeatureQueryView {
  summary,
  scheduleToday,
  scheduleTerms,
  scheduleWeeks,
  scheduleWeek,
  examArranged,
  examNotArranged,
  gradesScored,
  gradesMissing,
  signinPending,
  signinCompleted,
  evaluationPending,
  bykcDetail,
  bykcProfile,
  bykcChosenCourses,
  bykcStatistics,
  libbookAreas,
  libbookAreaDetail,
  libbookSeats,
  libbookBookings,
  ygdkRecords,
  cgyyPurposeTypes,
  cgyyDayInfo,
  cgyyOrders,
  cgyyOrderDetail,
  cgyyLockCode,
  spocDetail,
  judgeDetail,
  judgeBatchDetails,
}

/// Judge 批量详情查询使用的公开作业标识。
///
/// 该类型只包含用户从作业列表中选择的课程/作业编号，不携带上游载荷或会话材料。
@immutable
class JudgeAssignmentQueryKey {
  const JudgeAssignmentQueryKey({
    required this.courseId,
    required this.assignmentId,
  });

  final String courseId;
  final String assignmentId;

  @override
  int get hashCode => courseId.hashCode ^ assignmentId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JudgeAssignmentQueryKey &&
          runtimeType == other.runtimeType &&
          courseId == other.courseId &&
          assignmentId == other.assignmentId;
}

/// 领域读取查询参数。未提供的字段由 Core/bridge 采用当前稳定默认值；
/// UI 不拼接 URL，也不把该对象序列化为 raw payload。
@immutable
class FeatureQuery {
  const FeatureQuery({
    this.term,
    this.date,
    this.campus,
    this.floorId,
    this.section,
    this.week,
    this.page = 0,
    this.size = 20,
    this.view = FeatureQueryView.summary,
    this.premisesId,
    this.storeyId,
    this.areaId,
    this.startTime,
    this.endTime,
    this.segment,
    this.siteId,
    this.orderId,
    this.assignmentId,
    this.courseId,
    this.judgeKeys = const <JudgeAssignmentQueryKey>[],
    this.includeExpired = false,
  });

  final String? term;
  final DateTime? date;
  final int? campus;

  /// 空教室结果的本地楼层筛选，不改变 Core 的固定查询参数。
  final String? floorId;

  /// 空教室结果的本地节次筛选，按白名单 `availableSections` 文本匹配。
  final String? section;
  final int? week;
  final int page;
  final int size;
  final FeatureQueryView view;

  /// 各领域详情查询使用的公开标识。它们由用户从读取结果中选择，
  /// 不包含 Session、Cookie 或 token。
  final String? premisesId;
  final String? storeyId;
  final String? areaId;
  final String? startTime;
  final String? endTime;

  /// 图书馆预约使用的公开时段编号；读取座位时也随查询保留供预约确认使用。
  final String? segment;
  final int? siteId;
  final int? orderId;
  final String? assignmentId;
  final String? courseId;

  /// Judge 批量详情的公开键，顺序会传递给 Core 并保持在结果中。
  final List<JudgeAssignmentQueryKey> judgeKeys;
  final bool includeExpired;

  FeatureQuery copyWith({
    String? term,
    DateTime? date,
    int? campus,
    String? floorId,
    String? section,
    int? week,
    int? page,
    int? size,
    FeatureQueryView? view,
    String? premisesId,
    String? storeyId,
    String? areaId,
    String? startTime,
    String? endTime,
    String? segment,
    int? siteId,
    int? orderId,
    String? assignmentId,
    String? courseId,
    List<JudgeAssignmentQueryKey>? judgeKeys,
    bool? includeExpired,
  }) => FeatureQuery(
    term: term ?? this.term,
    date: date ?? this.date,
    campus: campus ?? this.campus,
    floorId: floorId ?? this.floorId,
    section: section ?? this.section,
    week: week ?? this.week,
    page: page ?? this.page,
    size: size ?? this.size,
    view: view ?? this.view,
    premisesId: premisesId ?? this.premisesId,
    storeyId: storeyId ?? this.storeyId,
    areaId: areaId ?? this.areaId,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    segment: segment ?? this.segment,
    siteId: siteId ?? this.siteId,
    orderId: orderId ?? this.orderId,
    assignmentId: assignmentId ?? this.assignmentId,
    courseId: courseId ?? this.courseId,
    judgeKeys: judgeKeys ?? this.judgeKeys,
    includeExpired: includeExpired ?? this.includeExpired,
  );
}
