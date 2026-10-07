part of 'projection.dart';

final class AcademicCacheMiss implements Exception {
  const AcademicCacheMiss();
}

final class AcademicValue<T> {
  const AcademicValue(this.data, this.route);
  final T data;
  final ConnectionMode route;
}

FeatureResult bridgeAcademicEvidence(
  FeatureResult result,
  DataEvidence? evidence,
) {
  if (evidence == null) return result;
  if (!evidence.complete)
    return FeatureResult.success(
      summary: '本次响应的完整性尚未确认',
      details: result.details,
      overview: result.overview,
      resolvedRoute: result.resolvedRoute,
      evidence: evidence,
    );
  return result.isEmpty
      ? FeatureResult.empty(
          overview: result.overview,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: result.summary,
          details: result.details,
          overview: result.overview,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        );
}

bool bridgeIsAcademicCacheQuery(FeatureId feature, FeatureQuery query) =>
    switch (feature) {
      FeatureId.schedule =>
        query.view == FeatureQueryView.scheduleTerms ||
            query.view == FeatureQueryView.scheduleWeeks ||
            query.view == FeatureQueryView.scheduleWeek ||
            (query.view == FeatureQueryView.summary &&
                query.term != null &&
                query.week != null),
      FeatureId.exam => {
        FeatureQueryView.summary,
        FeatureQueryView.examArranged,
        FeatureQueryView.examNotArranged,
      }.contains(query.view),
      FeatureId.grades => {
        FeatureQueryView.summary,
        FeatureQueryView.gradesScored,
        FeatureQueryView.gradesMissing,
      }.contains(query.view),
      FeatureId.classroom => true,
      _ => false,
    };
