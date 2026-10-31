import 'dart:async';
import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final _now = AgendaTime(
  rfc3339: '2026-03-24T12:00:00+08:00',
  timezone: 'Asia/Shanghai',
);
AgendaDraft _draft(String title) => AgendaDraft(
  content: AgendaContent(kind: AgendaKind.task, title: title, allDay: false),
  exdates: [],
);
final _superseded = throwsA(
  isA<AgendaException>().having(
    (e) => e.failure,
    '旧代次',
    AgendaFailure.superseded,
  ),
);
// 让当前事件的 microtask 队列收尾，不以时间长短推断业务完成。
Future<void> _turn() => Future<void>(() {});

void main() {
  for (final target in ['same', 'other', 'dispose']) {
    test('关闭等待已交付写入，$target 不能越过旧写入', () async {
      final backend = _Backend();
      final service = AgendaService(backend);
      await service.openAccount('same');
      final write = service.create(_draft('已交付'), _now);
      final rejected = expectLater(write, _superseded);
      await backend.started.future;
      // 清除尚未进入后端，关闭请求必须撤销这次旧代次调用。
      final queued = expectLater(service.clearLocalData(), _superseded);
      var closed = false;
      final closing =
          (target == 'dispose' ? service.dispose() : service.close()).then(
            (_) => closed = true,
          );
      await expectLater(service.get('old'), throwsA(isA<AgendaException>()));
      final opening = target == 'dispose' ? null : service.openAccount(target);
      try {
        await _turn();
        expect(closed, isFalse, reason: '仍有已交付的后端写入');
        expect(backend.accounts, ['same']);
      } finally {
        backend.release.complete();
        await rejected;
        await queued;
        await closing;
        await opening;
      }
      expect(backend.rows['same'], ['已交付']);
      expect(backend.clears, 0);
      if (target == 'dispose') {
        await expectLater(
          service.openAccount('same'),
          throwsA(isA<AgendaException>()),
        );
        expect(backend.active, isFalse);
      } else {
        await service.create(_draft('新代次'), _now);
        expect(
          backend.rows[target],
          target == 'same' ? ['已交付', '新代次'] : ['新代次'],
        );
        if (target == 'other') expect(backend.rows['same'], ['已交付']);
        await service.dispose();
      }
    });
  }

  test('已交付写入失败后关闭和重新打开仍可收尾', () async {
    final backend = _Backend()..fail = true;
    final service = AgendaService(backend);
    await service.openAccount('same');
    final rejected = expectLater(
      service.create(_draft('失败'), _now),
      _superseded,
    );
    await backend.started.future;
    final closing = service.close();
    final opening = service.openAccount('same');
    backend.release.complete();
    await rejected;
    await closing;
    await opening;
    expect(backend.rows['same'], isEmpty);
    backend.fail = false;
    await service.create(_draft('成功'), _now);
    expect(backend.rows['same'], ['成功']);
    await service.dispose();
  });

  final writes = <String, Future<Object?> Function(AgendaService)>{
    'create': (s) => s.create(_draft('排队'), _now),
    'edit': (s) => s.edit(
      'id',
      AgendaEditScope.all,
      null,
      _draft('改').content,
      null,
      _now,
    ),
    'delete': (s) => s.delete('id', AgendaEditScope.all, null, _now),
    'complete': (s) => s.complete('id', null, true, _now),
    'setOverlay': (s) => s.setOverlay(
      AgendaOverlayDraft(
        key: SchoolAgendaKey(source: 'spoc', upstreamId: 'synthetic'),
        completionOverride: false,
        hidden: true,
      ),
      _now,
    ),
    'clearOverlay': (s) => s.clearOverlay(
      SchoolAgendaKey(source: 'spoc', upstreamId: 'synthetic'),
      _now,
    ),
    'clearLocalData': (s) => s.clearLocalData(),
  };
  for (final entry in writes.entries) {
    test('排队的 ${entry.key} 在关闭后不进入后端', () async {
      final backend = _Backend();
      final service = AgendaService(backend);
      await service.openAccount('same');
      final first = expectLater(
        service.create(_draft('先行'), _now),
        _superseded,
      );
      await backend.started.future;
      final queued = expectLater(entry.value(service), _superseded);
      final closing = service.close();
      backend.release.complete();
      await first;
      await queued;
      await closing;
      expect(backend.invocations, ['create']);
      expect(backend.rows['same'], ['先行']);
    });
  }
}

class _Backend implements AgendaBackend {
  final started = Completer<void>();
  final release = Completer<void>();
  final accounts = <String>[];
  final rows = <String, List<String>>{};
  final invocations = <String>[];
  String? account;
  bool active = false;
  bool fail = false;
  int clears = 0;
  @override
  Future<void> openAccount(String id) async {
    account = id;
    active = true;
    accounts.add(id);
    rows.putIfAbsent(id, () => []);
  }

  @override
  Future<void> deactivate() async {
    active = false;
  }

  @override
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) async {
    invocations.add('create');
    final owner = account!;
    if (!started.isCompleted) started.complete();
    await release.future;
    if (fail) throw const AgendaException(AgendaFailure.unavailable);
    if (!active) throw const AgendaException(AgendaFailure.inactive);
    rows[owner]!.add(draft.content.title);
    return AgendaItem(
      id: 'id',
      content: draft.content,
      exdates: [],
      overrides: [],
      completions: [],
      createdAt: now,
      updatedAt: now,
      locallyModified: true,
    );
  }

  @override
  Future<int> clearLocalData() async {
    invocations.add('clearLocalData');
    clears++;
    final values = rows[account]!;
    final count = values.length;
    values.clear();
    return count;
  }

  @override
  Future<AgendaItem?> get(String id) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation.memberName.toString());
    return Future<void>.value();
  }
}
