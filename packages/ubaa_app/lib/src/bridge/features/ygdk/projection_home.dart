part of 'projection.dart';

YgdkHomeRecords bridgeYgdkHomeRecords(
  FeatureResult value,
  int classifyId,
  int page,
  int size, {
  UbaaErrorCode? error,
}) => YgdkHomeRecords(
  classifyId: classifyId,
  evidence: value.evidence,
  page: value.pagination?.page ?? page,
  size: value.pagination?.size ?? size,
  total: value.pagination?.total,
  hasMore: value.pagination?.hasMore,
  content: List.unmodifiable(
    value.details
        .map((v) => v.presentation)
        .whereType<YgdkRecordPresentation>(),
  ),
  errorCode: error,
);
