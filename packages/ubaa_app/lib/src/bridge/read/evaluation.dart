part of '../bridge_backend.dart';

Future<FeatureResult> _loadEvaluationFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.evaluation:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.evaluationPending:
          final result = await client.evaluationAll();
          final courses = query.view == FeatureQueryView.evaluationPending
              ? result.data.courses
                    .where((item) => !item.isEvaluated)
                    .toList(growable: false)
              : result.data.courses;
          final details = courses
              .map(
                (item) => FeatureDetail(
                  title: item.kcmc,
                  subtitle: item.bpmc,
                  fields: _compactFields(<FeatureField?>[
                    _field('状态', item.isEvaluated ? '已评' : '待评'),
                    _field('课程 ID', item.id),
                    _field('任务 ID', item.rwid),
                    _field('问卷 ID', item.wjid),
                    _field('课程代码', item.kcdm),
                    _field('模型 ID', item.msid),
                  ]),
                ),
              )
              .toList(growable: false);
          final progress = result.data.progress;
          final summary = query.view == FeatureQueryView.evaluationPending
              ? '待评 ${progress.pendingCourses} 门'
              : '已评 ${progress.evaluatedCourses}/${progress.totalCourses} 门';
          return FeatureResult.success(
            summary: summary,
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    default:
      throw StateError('unexpected feature: $feature');
  }
}
