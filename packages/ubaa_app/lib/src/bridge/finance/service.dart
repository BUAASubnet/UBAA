import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../contracts/backend.dart';
import '../../contracts/recovery.dart';
import '../../controller/error_mapper.dart';
import '../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import '../context.dart';
import '../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

/// 财务读取复用学校会话与账号缓存，公开安全错误。
class BridgeFinanceService implements FinanceService {
  BridgeFinanceService(this.context, this.recover);
  final BridgeContext context;
  final Future<RecoveredRouteSession> Function() recover;
  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BridgeError catch (e) {
      throw UbaaErrorMapper.fromException(bridgeMapError(e));
    } on BackendException catch (e) {
      throw UbaaErrorMapper.fromException(e);
    }
  }

  @override
  Future<FinanceSnapshot?> cached() => _call(() async {
    await bridgeAwaitOfflineScope(context);
    final cache = context.cache.handle, account = context.cache.account;
    if (cache == null || account == null) return null;
    final value = await cache.readFinance(route: BridgeConnectionMode.direct);
    if (context.cache.account?.id != account.id) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    if (value == null) return null;
    return _map(
      value.data,
      value.sourceRoute,
      value.fetchedAt.toInt(),
      true,
      true,
      null,
    );
  });
  @override
  Future<FinanceSnapshot> refresh() => _call(() async {
    await recover();
    await bridgeAwaitOfflineScope(context);
    final cache = context.cache.handle, account = context.cache.account;
    if (cache != null && account != null) {
      final value = await context.client.financeCached(cache: cache);
      if (context.cache.account?.id != account.id) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return _map(
        value.data,
        value.route.resolvedRoute,
        value.fetchedAt.toInt(),
        false,
        value.savedForOffline,
        value.saveError?.name,
      );
    }
    final value = await context.client.financeIncomes();
    return _map(
      value.data,
      value.route.resolvedRoute,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      false,
      false,
      null,
    );
  });
}

FinanceSnapshot _map(
  BridgeFinanceIncomes v,
  BridgeConnectionMode route,
  int at,
  bool cached,
  bool saved,
  String? error,
) => FinanceSnapshot(
  entries: v.entries
      .map(
        (e) => FinanceIncome(
          id: e.id,
          project: e.project,
          description: e.description,
          amountCents: e.amountCents?.toInt(),
          taxCents: e.taxCents?.toInt(),
          paidCents: e.paidCents?.toInt(),
          taxRate: e.taxRate,
          recordedDate: e.recordedDate,
          year: e.year,
          month: e.month,
        ),
      )
      .toList(),
  total: v.total,
  route: bridgeToConnectionMode(route),
  fetchedAt: DateTime.fromMillisecondsSinceEpoch(
    at.toInt() * 1000,
    isUtc: true,
  ),
  fromCache: cached,
  savedForOffline: saved,
  saveError: error,
);
