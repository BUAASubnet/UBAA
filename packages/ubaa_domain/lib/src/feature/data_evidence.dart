import 'package:meta/meta.dart';

/// 数据取得来源与当前认证状态无关。
enum DataOrigin { persisted, mixed, online }

/// 展示所依据的账号、时间与覆盖范围，不授予任何学校写资格。
@immutable
class DataEvidence {
  const DataEvidence({
    required this.accountId,
    required this.origin,
    required this.fetchedAt,
    required this.complete,
    required this.savedForOffline,
    this.scopeDate,
  });
  final String accountId;
  final DataOrigin origin;
  final DateTime fetchedAt;
  final bool complete;
  final bool savedForOffline;
  final String? scopeDate;
}
