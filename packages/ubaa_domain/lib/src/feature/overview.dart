import '../common/error.dart';
import 'presentation.dart';

/// 只读结果的集合级统计，不从局部搜索或分页重新计算。
sealed class FeatureOverview {
  const FeatureOverview();
}

final class SpocTermOverview extends FeatureOverview {
  const SpocTermOverview({required this.termCode, this.termName});
  final String termCode;
  final String? termName;
}

final class EvaluationProgressOverview extends FeatureOverview {
  const EvaluationProgressOverview({
    required this.totalCourses,
    required this.evaluatedCourses,
    required this.pendingCourses,
  });
  final int totalCourses;
  final int evaluatedCourses;
  final int pendingCourses;
}

/// 阳光集合概要来自公开统计，不由当前记录页重新计数。
final class YgdkOverview extends FeatureOverview {
  const YgdkOverview({
    required this.termCount,
    required this.classifyId,
    required this.classifyName,
    required this.defaultItemId,
    required this.defaultItemName,
    this.termId,
    this.termName,
    this.termTarget,
    this.weekCount,
    this.weekTarget,
    this.monthCount,
    this.monthTarget,
    this.dayCount,
    this.goodCount,
    this.records,
  });
  final int termCount, classifyId, defaultItemId;
  final String classifyName, defaultItemName;
  final int? termId, termTarget, weekCount, weekTarget;
  final int? monthCount, monthTarget, dayCount, goodCount;
  final String? termName;

  /// null表示尚未请求首页记录；空成功和局部失败由该对象分别表达。
  final YgdkHomeRecords? records;
}

final class YgdkHomeRecords {
  const YgdkHomeRecords({
    required this.page,
    required this.size,
    this.content = const [],
    this.total,
    this.hasMore,
    this.errorCode,
  });
  final int page, size;
  final List<YgdkRecordPresentation> content;
  final int? total;
  final bool? hasMore;
  final UbaaErrorCode? errorCode;
}

/// 单学期完整成绩集合，独立于已出/待出视图与本地搜索。
final class GradesTermOverview extends FeatureOverview {
  const GradesTermOverview({
    required this.requestTerm,
    required this.termCode,
    required this.grades,
  });
  final String requestTerm, termCode;
  final List<GradePresentation> grades;
}
