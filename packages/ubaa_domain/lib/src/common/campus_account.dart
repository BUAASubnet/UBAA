import 'package:meta/meta.dart';

import 'error.dart' show UiError;

/// 门户的身份与学院，仅用于资料展示，不参与登录判定。
@immutable
class PortalIdentity {
  const PortalIdentity({
    required this.identity,
    required this.department,
    required this.fetchedAt,
  });

  final String identity;
  final String department;
  final DateTime fetchedAt;
}

/// 保留上游十进制字符串与单位，不做基数换算。
@immutable
class CampusAmount {
  const CampusAmount({required this.value, required this.unit});

  final String value;
  final String unit;
}

/// 单项读取结果；有效零值与失败分开表示。
@immutable
sealed class CampusMetric<T> {
  const CampusMetric({required this.fetchedAt});
  final DateTime fetchedAt;
}

final class CampusMetricValue<T> extends CampusMetric<T> {
  const CampusMetricValue(this.value, {required super.fetchedAt});
  final T value;
}

final class CampusMetricFailure<T> extends CampusMetric<T> {
  const CampusMetricFailure(this.message, {required super.fetchedAt});

  /// 已脱敏的用户可读说明。
  final String message;
}

/// 门户五项账户指标，任一项失败不影响其他项；失败项可能显示上次成功值。
@immutable
class CampusMetrics {
  const CampusMetrics({
    required this.networkBalance,
    required this.cardBalance,
    required this.unreadMail,
    required this.borrowedBooks,
    required this.cloudStorageRemaining,
  });

  // 本地快照可能缺少从未成功取得的项，此时为 null。
  final CampusMetric<CampusAmount>? networkBalance;
  final CampusMetric<CampusAmount>? cardBalance;
  final CampusMetric<int>? unreadMail;
  final CampusMetric<int>? borrowedBooks;
  final CampusMetric<CampusAmount>? cloudStorageRemaining;
}

/// 一个网络产品的流量；两项剩余均不含套餐，不合成总量。
@immutable
class NetworkProductUsage {
  const NetworkProductUsage({
    required this.productName,
    required this.used,
    required this.freeRemaining,
    required this.billableRemaining,
  });

  final String productName;
  final CampusAmount used;
  final CampusAmount freeRemaining;
  final CampusAmount billableRemaining;
}

@immutable
class NetworkUsage {
  const NetworkUsage({
    required this.products,
    required this.fetchedAt,
    this.remainingExcludesPackages = true,
  });

  final List<NetworkProductUsage> products;
  final bool remainingExcludesPackages;
  final DateTime fetchedAt;
}

/// 一组校园账户读取的界面状态：未开始、读取中、成功或失败。
@immutable
class CampusSection<T> {
  const CampusSection.idle() : data = null, error = null, loading = false;
  const CampusSection.loading([this.data]) : error = null, loading = true;
  const CampusSection.ready(T this.data) : error = null, loading = false;
  const CampusSection.failed(String this.error, [this.data]) : loading = false;

  final T? data;
  final String? error;
  final bool loading;
}

/// “我的”页面所需的门户资料、账户指标和网费流量。
@immutable
class CampusAccountOverview {
  const CampusAccountOverview({
    this.identity = const CampusSection.idle(),
    this.metrics = const CampusSection.idle(),
    this.network = const CampusSection.idle(),
  });

  final CampusSection<PortalIdentity> identity;
  final CampusSection<CampusMetrics> metrics;
  final CampusSection<NetworkUsage> network;
}

/// 本机保存的上次结果；缺少的组为 null。
@immutable
class CampusAccountSnapshot {
  const CampusAccountSnapshot({this.identity, this.metrics, this.network});
  final PortalIdentity? identity;
  final CampusMetrics? metrics;
  final NetworkUsage? network;

  bool get isEmpty => identity == null && metrics == null && network == null;
}

/// “我的”页面的读取入口；在线读取成功时同时更新本机快照。
/// 在线失败时抛出可展示的 [UiError]。
abstract interface class CampusAccountService {
  /// 只读本机快照，不访问学校；不可用时返回空快照。
  Future<CampusAccountSnapshot> cached();
  Future<PortalIdentity> identity();
  Future<CampusMetrics> metrics();
  Future<NetworkUsage> networkUsage();
}
