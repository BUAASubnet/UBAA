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
    FeatureQuery? query,
    GradesTermOverview? overview,
    Iterable<FeatureDetail> details = const [],
  }) : overview = overview == null
           ? null
           : GradesTermOverview(
               requestTerm: overview.requestTerm,
               termCode: overview.termCode,
               grades: List.unmodifiable(overview.grades),
             ),
       readContext = FeatureReadContext(query: query, requestRevision: 0),
       details = List.unmodifiable(
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
  final GradesTermOverview? overview;
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
