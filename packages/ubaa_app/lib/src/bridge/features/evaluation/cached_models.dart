part of 'projection.dart';

bool bridgeIsEvaluationCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.evaluation &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.evaluationPending,
    }.contains(query.view);
