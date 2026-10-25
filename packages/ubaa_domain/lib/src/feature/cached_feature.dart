import 'catalog.dart';
import 'query.dart';
import 'overview.dart';
import 'data_evidence.dart';
import 'result.dart';
import 'read_context.dart';
import '../common/route.dart';

/// 缓存到界面的单向只读投影；绝不恢复线上快照中的写动作。
final class CachedFeatureProjection {
  CachedFeatureProjection({
    required this.feature,
    required this.accountId,
    required this.route,
    required this.fetchedAt,
    required this.complete,
    this.scopeDate,
    this.pagination,
    FeatureQuery? query,
    FeatureOverview? overview,
    Iterable<FeatureDetail> details = const [],
  }) : overview = readonlyFeatureOverview(overview),
       readContext = FeatureReadContext(query: query, requestRevision: 0),
       details = readonlyFeatureDetails(details);
  final FeaturePagination? pagination;
  final FeatureOverview? overview;
  final FeatureReadContext readContext;
  final FeatureId feature;
  final String accountId;
  final ConnectionMode route;
  final DateTime fetchedAt;
  final String? scopeDate;
  final bool complete;
  final List<FeatureDetail> details;

  FeatureSnapshot toSnapshot() => FeatureSnapshot(
    feature: feature,
    status: FeatureLoadStatus.stale,
    readContext: readContext,
    details: details,
    overview: overview,
    pagination: pagination,
    resolvedRoute: route,
    updatedAt: fetchedAt,
    evidence: DataEvidence(
      accountId: accountId,
      origin: DataOrigin.persisted,
      fetchedAt: fetchedAt,
      complete: complete,
      savedForOffline: true,
      scopeDate: scopeDate,
    ),
  );
}

/// 共用不可写字段投影，不改变调用方原来源或取得时间。
List<FeatureDetail> readonlyFeatureDetails(Iterable<FeatureDetail> details) =>
    List.unmodifiable(
      details.map(
        (detail) => FeatureDetail(
          title: detail.title,
          subtitle: detail.subtitle,
          fields: List.unmodifiable(detail.fields),
          presentation: detail.presentation,
          readNavigation: detail.readNavigation,
        ),
      ),
    );

FeatureOverview? readonlyFeatureOverview(FeatureOverview? overview) =>
    switch (overview) {
      HomeScheduleOverview value => HomeScheduleOverview(
        date: value.date,
        week: value.week,
      ),
      ScheduleWeekOverview value => ScheduleWeekOverview(
        code: value.code,
        sectionTimes: List.unmodifiable(value.sectionTimes),
      ),
      EvaluationProgressOverview value => EvaluationProgressOverview(
        totalCourses: value.totalCourses,
        evaluatedCourses: value.evaluatedCourses,
        pendingCourses: value.pendingCourses,
      ),
      BykcChosenOverview value => BykcChosenOverview(
        semesterStart: value.semesterStart,
        semesterEnd: value.semesterEnd,
      ),
      GradesTermOverview value => GradesTermOverview(
        requestTerm: value.requestTerm,
        termCode: value.termCode,
        grades: List.unmodifiable(value.grades),
      ),
      SpocTermOverview value => SpocTermOverview(
        termCode: value.termCode,
        termName: value.termName,
      ),
      YgdkOverview value => YgdkOverview(
        termCount: value.termCount,
        classifyId: value.classifyId,
        classifyName: value.classifyName,
        defaultItemId: value.defaultItemId,
        defaultItemName: value.defaultItemName,
        termId: value.termId,
        termName: value.termName,
        termTarget: value.termTarget,
        weekCount: value.weekCount,
        weekTarget: value.weekTarget,
        monthCount: value.monthCount,
        monthTarget: value.monthTarget,
        dayCount: value.dayCount,
        goodCount: value.goodCount,
        records: value.records == null
            ? null
            : YgdkHomeRecords(
                page: value.records!.page,
                size: value.records!.size,
                classifyId: value.records!.classifyId,
                evidence: value.records!.evidence,
                content: List.unmodifiable(value.records!.content),
                total: value.records!.total,
                hasMore: value.records!.hasMore,
                errorCode: value.records!.errorCode,
              ),
      ),
      _ => null,
    };
