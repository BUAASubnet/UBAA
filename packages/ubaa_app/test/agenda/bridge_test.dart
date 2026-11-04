import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/bridge/agenda/backend.dart';
import 'package:ubaa_app/src/bridge/agenda/school.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const _alias = '00000000000000000000000000000001';
void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.handle = _Handle();
    api.accounts.clear();
  });
  test('生产后端日程独立打开，日程损坏不映射为可重建缓存故障', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.agenda.openAccount(_alias);
    expect(api.accounts, [_alias]);
    api.handle.getFailure = const BridgeAgendaError(
      failure: BridgeAgendaFailure.corrupt,
    );
    await expectLater(
      backend.agenda.get('synthetic-id'),
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '日程损坏',
          AgendaFailure.corrupt,
        ),
      ),
    );
    await expectLater(
      backend.clearOfflineAccount(accountId: _alias),
      throwsA(
        isA<BackendException>().having(
          (e) => e.cacheFailure,
          '未确认缓存清除',
          CacheMaintenanceFailure.unavailable,
        ),
      ),
    );
    await backend.dispose();
    expect(api.handle.active, isFalse);
    await expectLater(
      backend.agenda.unsyncedCount(),
      throwsA(isA<AgendaException>()),
    );
  });
  test('学校查询固定路线，清理期间返回的旧缓存结果降级为本地查询', () async {
    final context = BridgeContext(_Client(), configDirectory: '/synthetic');
    final backend = BridgeAgendaBackend(context);
    await backend.openAccount(_alias);
    context.cache.account = const LocalAccount(
      id: _alias,
      username: 'synthetic',
    );
    context.cache.handle = _Cache();
    api.handle.cacheGate = Completer<BridgeAgendaQueryResult>();
    final reading = backend.query(
      AgendaQuery(
        route: ConnectionMode.webvpn,
        term: 'synthetic',
        from: '2026-03-24',
        to: '2026-03-30',
        now: AgendaTime(
          rfc3339: '2026-03-24T12:00:00+08:00',
          timezone: 'Asia/Shanghai',
        ),
        includeHidden: false,
        ygdkEnabled: false,
        ygdkWeekDone: true,
        ygdkTermDone: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(api.handle.request!.route, BridgeConnectionMode.webVpn);
    expect(api.handle.request!.ygdkEnabled, isFalse);
    expect(api.handle.request!.ygdkWeekDone, isTrue);
    context.cache.generation++;
    api.handle.cacheGate!.complete(
      const BridgeAgendaQueryResult(entries: [], sources: []),
    );
    final result = await reading;
    expect(result.schoolCacheFailure, CacheMaintenanceFailure.superseded);
    expect(api.handle.localQueries, 1);
    await backend.deactivate();
  });
  test('缓存已打开但无学期时导出本机事项，有学期的缓存故障继续失败', () async {
    final context = BridgeContext(_Client(), configDirectory: '/synthetic');
    final backend = BridgeAgendaBackend(context);
    await backend.openAccount(_alias);
    context.cache.account = const LocalAccount(
      id: _alias,
      username: 'synthetic',
    );
    context.cache.handle = _Cache();
    AgendaQuery query(String term) => AgendaQuery(
      route: ConnectionMode.direct,
      term: term,
      from: '2026-11-01',
      to: '2026-11-12',
      now: AgendaTime(
        rfc3339: '2026-11-05T09:00:00+08:00',
        timezone: 'Asia/Shanghai',
      ),
      includeHidden: false,
      ygdkEnabled: false,
      ygdkWeekDone: false,
      ygdkTermDone: false,
    );
    expect((await backend.exportIcs(query(''), true)).exportedCount, 1);
    expect(
      (await backend.exportIcs(query('synthetic'), true)).exportedCount,
      2,
    );
    for (final failure in [
      BridgeAgendaFailure.corrupt,
      BridgeAgendaFailure.inactive,
      BridgeAgendaFailure.invalidInput,
    ]) {
      api.handle.exportFailure = BridgeAgendaError(failure: failure);
      await expectLater(
        backend.exportIcs(query('synthetic'), true),
        throwsA(
          isA<AgendaException>().having(
            (e) => e.failure.name,
            '缓存错误保留',
            failure.name,
          ),
        ),
      );
    }
    await backend.deactivate();
  });
  test('不完整时间、原始完成状态和跳转字段逐字段保留，集合不可变', () {
    final timing = fromAgendaTiming(
      const BridgeAgendaTiming(
        kind: BridgeAgendaTimingKind.period,
        end: BridgeAgendaTime(
          rfc3339: '2026-03-24T12:00:00+08:00',
          timezone: 'Asia/Shanghai',
        ),
      ),
    );
    expect(timing.start, isNull);
    expect(timing.end!.rfc3339, '2026-03-24T12:00:00+08:00');
    final status = fromAgendaUpstreamStatus(
      const BridgeAgendaUpstreamStatus(
        feature: BridgeAgendaFeature.judge,
        completed: true,
        submission: BridgeAgendaSubmission.submitted,
        text: '原始状态',
      ),
    );
    expect(status.completed, isTrue);
    expect(status.submission, AgendaSubmission.submitted);
    final navigation = fromAgendaNavigation(
      const BridgeAgendaNavigation(
        feature: BridgeAgendaFeature.schedule,
        term: 'synthetic',
        week: 3,
        courseCode: 'synthetic-course',
        serial: '01',
        day: 2,
        section: 1,
      ),
    );
    expect(navigation.serial, '01');
    expect(navigation.week, 3);
    final source = <AgendaEntry>[];
    final result = AgendaQueryResult(entries: source, sources: []);
    source.clear();
    expect(() => result.entries.clear(), throwsUnsupportedError);
  });
}

class _Api extends RustLibApi {
  _Handle handle = _Handle();
  final accounts = <String>[];
  @override
  Future<BridgeAgendaStore> crateApiAgendaBridgeAgendaStoreOpen({
    required String configDir,
    required String accountId,
  }) async {
    accounts.add(accountId);
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Handle implements BridgeAgendaStore {
  bool active = false;
  BridgeAgendaError? getFailure;
  Completer<BridgeAgendaQueryResult>? cacheGate;
  BridgeAgendaQuery? request;
  int localQueries = 0;
  BridgeAgendaError? exportFailure;
  @override
  Future<BridgeAgendaExport> exportIcs({
    required BridgeAgendaQuery query,
    required bool includeCompleted,
  }) async => const BridgeAgendaExport(
    ics: '本机快照',
    exportedCount: 1,
    skippedUnknownTimeCount: 0,
  );
  @override
  Future<BridgeAgendaExport> exportWithCache({
    required BridgeOfflineCache cache,
    required BridgeAgendaQuery query,
    required bool includeCompleted,
  }) async {
    if (query.term.isEmpty)
      throw const BridgeAgendaError(failure: BridgeAgendaFailure.invalidInput);
    if (exportFailure != null) throw exportFailure!;
    return const BridgeAgendaExport(
      ics: '学校与本机快照',
      exportedCount: 2,
      skippedUnknownTimeCount: 0,
    );
  }

  @override
  Future<void> activate() async {
    active = true;
  }

  @override
  Future<void> deactivate() async {
    active = false;
  }

  @override
  Future<BridgeAgendaItem?> get_({required String itemId}) async {
    if (getFailure != null) throw getFailure!;
    return null;
  }

  @override
  Future<BridgeAgendaQueryResult> queryWithCache({
    required BridgeOfflineCache cache,
    required BridgeAgendaQuery query,
  }) {
    request = query;
    return cacheGate!.future;
  }

  @override
  Future<BridgeAgendaQueryResult> queryLocal({
    required BridgeAgendaQuery query,
  }) async {
    localQueries++;
    return const BridgeAgendaQueryResult(entries: [], sources: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  @override
  int contractVersion() => 47;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
