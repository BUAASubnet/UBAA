import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../contracts/backend.dart' show BackendException;
import '../../controller/error_mapper.dart' show UbaaErrorMapper;
import '../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import '../context.dart';
import '../support/mapping.dart' show bridgeMapError, bridgeTypedErrorCode;

/// 门户与网费读取的桥接投影：先读本机快照，在线成功时同时保存。
///
/// 缓存不可用时退回纯在线读取，不另建明文文件；错误统一转为安全的界面错误。
class BridgeCampusAccountService implements CampusAccountService {
  BridgeCampusAccountService(this._context);
  final BridgeContext _context;

  BridgeClient get _client => _context.client;

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BridgeError catch (error) {
      throw UbaaErrorMapper.fromException(bridgeMapError(error));
    } on BackendException catch (error) {
      throw UbaaErrorMapper.fromException(error);
    }
  }

  /// 有缓存句柄时走带保存的刷新，并确认期间账号未变化。
  Future<BridgeCampusSection?> _refresh(BridgeCampusCacheQuery query) async {
    await bridgeAwaitOfflineScope(_context);
    final cache = _context.cache.handle, account = _context.cache.account;
    if (cache == null || account == null) return null;
    final value = await _client.campusCached(cache: cache, query: query);
    if (_context.cache.account?.id != account.id) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return value.data;
  }

  @override
  Future<CampusAccountSnapshot> cached() async {
    try {
      await bridgeAwaitOfflineScope(_context);
    } on Object {
      return const CampusAccountSnapshot();
    }
    final cache = _context.cache.handle, account = _context.cache.account;
    if (cache == null || account == null) return const CampusAccountSnapshot();

    // 两条路线的快照属于同一账号，取最近的一份。
    Future<BridgeCachedCampusSection?> newest(
      BridgeCampusCacheQuery query,
    ) async {
      BridgeCachedCampusSection? best;
      for (final route in BridgeConnectionMode.values) {
        try {
          final value = await cache.readCampus(route: route, query: query);
          if (value == null || value.sourceRoute != route) continue;
          if (best == null || value.fetchedAt > best.fetchedAt) best = value;
        } on BridgeError {
          // 单个范围损坏只放弃该快照，不影响在线刷新。
        }
      }
      return best;
    }

    final profile = await newest(BridgeCampusCacheQuery.profile);
    final metrics = await newest(BridgeCampusCacheQuery.metrics);
    final network = await newest(BridgeCampusCacheQuery.networkUsage);
    if (_context.cache.account?.id != account.id) {
      return const CampusAccountSnapshot();
    }
    return CampusAccountSnapshot(
      identity: profile?.data.profile == null
          ? null
          : _identity(profile!.data.profile!),
      metrics: metrics?.data.metrics == null
          ? null
          : _metrics(metrics!.data.metrics!),
      network: network?.data.networkUsage == null
          ? null
          : _network(network!.data.networkUsage!),
    );
  }

  @override
  Future<PortalIdentity> identity() => _call(() async {
    final section = await _refresh(BridgeCampusCacheQuery.profile);
    if (section != null) {
      final value = section.profile;
      if (value == null) {
        throw const BackendException(UbaaErrorCode.internalError);
      }
      return _identity(value);
    }
    return _identity((await _client.portalProfile()).data);
  });

  @override
  Future<CampusMetrics> metrics() => _call(() async {
    final section = await _refresh(BridgeCampusCacheQuery.metrics);
    if (section != null) {
      final value = section.metrics;
      if (value == null) {
        throw const BackendException(UbaaErrorCode.internalError);
      }
      return _metrics(value);
    }
    return _metrics((await _client.campusMetrics()).data);
  });

  @override
  Future<NetworkUsage> networkUsage() => _call(() async {
    final section = await _refresh(BridgeCampusCacheQuery.networkUsage);
    if (section != null) {
      final value = section.networkUsage;
      if (value == null) {
        throw const BackendException(UbaaErrorCode.internalError);
      }
      return _network(value);
    }
    return _network((await _client.networkUsage()).data);
  });
}

/// Core 时间戳为 Unix 秒。
DateTime _time(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

PortalIdentity _identity(BridgePortalProfile value) => PortalIdentity(
  identity: value.identity,
  department: value.department,
  fetchedAt: _time(value.fetchedAt),
);

NetworkUsage _network(BridgeNetworkUsage data) => NetworkUsage(
  products: [
    for (final product in data.products)
      NetworkProductUsage(
        productName: product.productName,
        used: _amount(product.used),
        freeRemaining: _amount(product.freeRemaining),
        billableRemaining: _amount(product.billableRemaining),
      ),
  ],
  remainingExcludesPackages: data.remainingExcludesPackages,
  fetchedAt: _time(data.fetchedAt),
);

CampusMetrics _metrics(BridgeCampusMetrics data) => CampusMetrics(
  networkBalance: _amountMetric(data.networkBalance),
  cardBalance: _amountMetric(data.cardBalance),
  unreadMail: _countMetric(data.unreadMail),
  borrowedBooks: _countMetric(data.borrowedBooks),
  cloudStorageRemaining: _amountMetric(data.cloudStorageRemaining),
);

CampusAmount _amount(BridgeCampusAmount value) =>
    CampusAmount(value: value.value, unit: value.unit);

String _failureMessage(BridgeCampusMetricFailure failure) =>
    UbaaErrorMapper.fromCode(bridgeTypedErrorCode(failure.code)).message;

/// 既无值也无失败表示快照中尚未取得该项。
CampusMetric<CampusAmount>? _amountMetric(BridgeCampusAmountMetric metric) {
  final fetchedAt = _time(metric.fetchedAt);
  final value = metric.value, failure = metric.failure;
  if (value != null && failure == null) {
    return CampusMetricValue(_amount(value), fetchedAt: fetchedAt);
  }
  if (failure != null) {
    return CampusMetricFailure(_failureMessage(failure), fetchedAt: fetchedAt);
  }
  return null;
}

CampusMetric<int>? _countMetric(BridgeCampusCountMetric metric) {
  final fetchedAt = _time(metric.fetchedAt);
  final value = metric.value, failure = metric.failure;
  if (value != null && value >= 0 && failure == null) {
    return CampusMetricValue(value, fetchedAt: fetchedAt);
  }
  if (failure != null) {
    return CampusMetricFailure(_failureMessage(failure), fetchedAt: fetchedAt);
  }
  return null;
}
