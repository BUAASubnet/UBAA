import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../context.dart';
import 'models.dart';
import 'school.dart';
import '../home/agenda.dart';
import '../support/mapping.dart' show bridgeMapError;

/// 只按安全索引提供的别名打开日程，不读取缓存密钥，也不触发学校请求。
final class BridgeAgendaBackend
    implements
        AgendaBackend,
        AgendaExportBackend,
        AgendaDraftBackend,
        AgendaSyncBackend {
  BridgeAgendaBackend(this.context);
  final BridgeContext context;
  BridgeAgendaStore? _handle;
  BridgeAgendaSyncService? _syncHandle;
  String? _account;
  bool _opened = false;
  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      final binding = context.sharedAccount;
      if (context.closed) throw const AgendaException(AgendaFailure.inactive);
      await binding?.validate();
      if (context.closed) throw const AgendaException(AgendaFailure.inactive);
      final result = await action();
      await binding?.commit(() {});
      if (!identical(binding, context.sharedAccount))
        throw const AgendaException(AgendaFailure.superseded);
      return result;
    } on LocalAccountConflict {
      throw const AgendaException(AgendaFailure.superseded);
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
  Future<bool> syncEnabled() => _call(() => _store.syncEnabled());
  @override
  Future<void> openAccount(String accountId) => _call(() async {
    final directory = context.configDirectory;
    if (directory == null) {
      throw const AgendaException(AgendaFailure.unavailable);
    }
    if (context.sharedAccount != null &&
        context.sharedAccount!.account.id != accountId)
      throw const AgendaException(AgendaFailure.superseded);
    final native = context.nativeAccount;
    final handle = native == null
        ? await BridgeAgendaStore.open(
            configDir: directory,
            accountId: accountId,
          )
        : await BridgeAgendaStore.openShared(
            configDir: directory,
            accountId: accountId,
            scope: native,
          );
    // 即使 activate 失败，后续关闭也能触达已经打开的句柄。
    _handle = handle;
    _account = accountId;
    await handle.activate();
    _opened = true;
  });
  @override
  Future<void> deactivate() async {
    _opened = false;
    _syncHandle?.dispose();
    _syncHandle = null;
    final handle = _handle;
    handle?.dispose();
    _handle = null;
    _account = null;
  }

  @override
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now) {
    final confirmed = action == AgendaSyncAction.createConfirmed;
    final confirmedStore = _handle;
    final confirmedBinding = context.sharedAccount;
    final BridgeAgendaSyncScope? scope;
    try {
      scope = confirmed ? context.client.captureAgendaSyncScope() : null;
    } on BridgeAgendaSyncError catch (error) {
      _throwSyncError(error);
    }
    return () => _call(() async {
      if (confirmed &&
          (!identical(confirmedStore, _handle) ||
              !identical(confirmedBinding, context.sharedAccount))) {
        throw const AgendaException(AgendaFailure.superseded);
      }

      final store = _store;
      var handle = _syncHandle;
      if (handle == null) {
        final opened = await BridgeAgendaSyncService.open(
          agenda: store,
          configDir: context.configDirectory!,
        );
        if (!identical(store, _handle) || context.closed) {
          opened.dispose();
          throw const AgendaException(AgendaFailure.superseded);
        }
        _syncHandle = handle = opened;
      }
      try {
        final client = context.client;
        final time = toAgendaTime(now);
        final result = scope == null
            ? await client.syncAgenda(
                service: handle,
                action: BridgeAgendaSyncAction.values.byName(action.name),
                now: time,
              )
            : await client.createAgendaSyncConfirmed(
                service: handle,
                now: time,
                scope: scope,
              );
        if (!identical(store, _handle) || context.closed)
          throw const AgendaException(AgendaFailure.superseded);
        return AgendaSyncReport(
          status: AgendaSyncStatus.values.byName(result.status.name),
          pendingCount: result.pendingCount,
          changedCount: result.changedCount,
        );
      } on BridgeAgendaSyncError catch (error) {
        _throwSyncError(error);
      }
    });
  }

  Never _throwSyncError(BridgeAgendaSyncError error) {
    if (error.local != null) {
      throw AgendaException(AgendaFailure.values.byName(error.local!.name));
    }
    if (error.remote != null) throw bridgeMapError(error.remote!);
    throw const AgendaException(AgendaFailure.unavailable);
  }

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
  Future<AgendaExportResult> exportIcs(
    AgendaQuery query,
    bool includeCompleted,
  ) => _call(() async {
    final handle = _store;
    final generation = context.cache.generation;
    final cache = context.cache.account?.id == _account
        ? context.cache.handle
        : null;
    final value = cache == null || query.term.trim().isEmpty
        ? await handle.exportIcs(
            query: toAgendaQuery(query),
            includeCompleted: includeCompleted,
          )
        : await handle.exportWithCache(
            cache: cache,
            query: toAgendaQuery(query),
            includeCompleted: includeCompleted,
          );
    if (generation != context.cache.generation)
      throw const AgendaException(AgendaFailure.superseded);
    return AgendaExportResult(
      ics: value.ics,
      exportedCount: value.exportedCount,
      skippedUnknownTimeCount: value.skippedUnknownTimeCount,
    );
  });
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async {
    final values = bridgeHomeAgendaInputs(request);
    final ctx = bridgeHomeAgendaContext(request);
    // 不等待 openAccount、安全索引或缓存密钥。已打开的同账号日程才叠加覆盖。
    final handle = _opened && _account == request.accountId ? _handle : null;
    AgendaFailure? failure;
    List<BridgeAgendaEntry> rows;
    if (handle != null) {
      try {
        rows = await handle.projectHome(values: values, context: ctx);
        return bridgeHomeTodoProjection(rows, request);
      } on BridgeAgendaError catch (e) {
        failure = AgendaFailure.values.byName(e.failure.name);
      }
    }
    rows = await agendaProjectHome(values: values, context: ctx);
    return bridgeHomeTodoProjection(rows, request, overlayFailure: failure);
  }

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
  Future<String?> editDraft(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaDraft draft,
    AgendaTime now,
  ) => _call(
    () => _store.editDraft(
      itemId: id,
      scope: toAgendaEditScope(scope),
      at: at == null ? null : toAgendaTime(at),
      draft: toAgendaDraft(draft),
      now: toAgendaTime(now),
    ),
  );
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
