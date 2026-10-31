import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../context.dart';
import 'models.dart';
import 'school.dart';

/// 只按安全索引提供的别名打开日程，不读取缓存密钥，也不触发学校请求。
final class BridgeAgendaBackend implements AgendaBackend {
  BridgeAgendaBackend(this.context);
  final BridgeContext context;
  BridgeAgendaStore? _handle;
  String? _account;
  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BridgeAgendaError catch (e) {
      throw AgendaException(switch (e.failure) {
        BridgeAgendaFailure.unavailable => AgendaFailure.unavailable,
        BridgeAgendaFailure.invalidInput => AgendaFailure.invalidInput,
        BridgeAgendaFailure.corrupt => AgendaFailure.corrupt,
        BridgeAgendaFailure.unsupportedVersion =>
          AgendaFailure.unsupportedVersion,
        BridgeAgendaFailure.inactive => AgendaFailure.inactive,
        BridgeAgendaFailure.superseded => AgendaFailure.superseded,
        BridgeAgendaFailure.capacity => AgendaFailure.capacity,
      });
    }
  }

  BridgeAgendaStore get _store =>
      _handle ?? (throw const AgendaException(AgendaFailure.inactive));
  @override
  Future<void> openAccount(String accountId) => _call(() async {
    final directory = context.configDirectory;
    if (directory == null) {
      throw const AgendaException(AgendaFailure.unavailable);
    }
    final handle = await BridgeAgendaStore.open(
      configDir: directory,
      accountId: accountId,
    );
    // 即使 activate 失败，后续关闭也能触达已经打开的句柄。
    _handle = handle;
    _account = accountId;
    await handle.activate();
  });
  @override
  Future<void> deactivate() => _call(() async {
    final handle = _handle;
    await handle?.deactivate();
    _handle = null;
    _account = null;
  });
  @override
  Future<AgendaQueryResult> query(AgendaQuery query) => _call(() async {
    final handle = _store;
    final cache = context.cache;
    final generation = cache.generation;
    final school = cache.account?.id == _account ? cache.handle : null;
    final request = toAgendaQuery(query);
    if (school == null) {
      return fromAgendaQueryResult(await handle.queryLocal(query: request));
    }
    final value = await handle.queryWithCache(cache: school, query: request);
    if (generation != cache.generation || cache.account?.id != _account) {
      final local = fromAgendaQueryResult(
        await handle.queryLocal(query: request),
      );
      return AgendaQueryResult(
        entries: local.entries,
        sources: local.sources,
        schoolCacheFailure: CacheMaintenanceFailure.superseded,
      );
    }
    return fromAgendaQueryResult(value);
  });
  @override
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) => _call(
    () async => fromAgendaItem(
      await _store.create(draft: toAgendaDraft(draft), now: toAgendaTime(now)),
    ),
  );
  @override
  Future<AgendaItem?> get(String itemId) => _call(() async {
    final v = await _store.get_(itemId: itemId);
    return v == null ? null : fromAgendaItem(v);
  });
  @override
  Future<String?> edit(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  ) => _call(
    () => _store.edit(
      itemId: itemId,
      scope: toAgendaEditScope(scope),
      at: at == null ? null : toAgendaTime(at),
      content: toAgendaContent(content),
      rrule: rrule,
      now: toAgendaTime(now),
    ),
  );
  @override
  Future<void> delete(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  ) => _call(
    () => _store.delete(
      itemId: itemId,
      scope: toAgendaEditScope(scope),
      at: at == null ? null : toAgendaTime(at),
      now: toAgendaTime(now),
    ),
  );
  @override
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  ) => _call(
    () => _store.complete(
      itemId: itemId,
      at: at == null ? null : toAgendaTime(at),
      completed: completed,
      now: toAgendaTime(now),
    ),
  );
  @override
  Future<void> setOverlay(AgendaOverlayDraft value, AgendaTime now) => _call(
    () => _store.setOverlay(
      overlay: toAgendaOverlayDraft(value),
      now: toAgendaTime(now),
    ),
  );
  @override
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key) => _call(() async {
    final v = await _store.overlay(key: toSchoolAgendaKey(key));
    return v == null ? null : fromAgendaOverlay(v);
  });
  @override
  Future<void> clearOverlay(SchoolAgendaKey key, AgendaTime now) => _call(
    () => _store.clearOverlay(
      key: toSchoolAgendaKey(key),
      now: toAgendaTime(now),
    ),
  );
  @override
  Future<int> unsyncedCount() => _call(() => _store.unsyncedCount());
  @override
  Future<int> clearLocalData() => _call(() => _store.clearLocalData());
  @override
  Future<TeachingWeekRule> teachingWeekRule(TeachingWeekInput input) => _call(
    () async => fromTeachingWeekRule(
      await agendaTeachingWeekRule(input: toTeachingWeekInput(input)),
    ),
  );
}
