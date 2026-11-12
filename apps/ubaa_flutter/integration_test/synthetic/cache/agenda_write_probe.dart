import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
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
    '旧写入结果',
    AgendaFailure.superseded,
  ),
);

/// 可控门只存在于测试适配器，实际读写经过生产 Bridge/Core 和 SQLite。
Future<void> probeAgendaWriteFence(String directory) async {
  const alias = '00000000000000000000000000000004';
  const other = '00000000000000000000000000000005';
  for (final clearing in [false, true]) {
    final backend = await BridgeBackend.open(directory);
    final gate = _GatedBackend(backend.agenda, clearing);
    final agenda = AgendaService(gate);
    var disposed = false;
    try {
      await agenda.openAccount(alias);
      await backend.agenda.clearLocalData();
      final original = await backend.agenda.create(_draft('原记录'), _now);
      final writing = clearing
          ? agenda.clearLocalData()
          : agenda.create(_draft('已交付写入'), _now);
      final rejected = expectLater(writing, _superseded);
      await gate.started.future;
      // 尚未进入后端的清除在 close 时撤销，不能清掉重新登录后的内容。
      final queued = expectLater(agenda.clearLocalData(), _superseded);
      var closed = false;
      final closing = agenda.close().then((_) => closed = true);
      final reopening = agenda.openAccount(alias);
      await Future<void>(() {});
      final closedBeforeRelease = closed;
      gate.release.complete();
      await rejected;
      await queued;
      await closing;
      await reopening;
      final fresh = await agenda.create(_draft('新代次记录'), _now);
      // 重建整个生产后端，避免只从同一服务内存读取结果。
      await agenda.dispose();
      await backend.dispose();
      disposed = true;
      final rebuilt = await BridgeBackend.open(directory);
      try {
        await rebuilt.agenda.openAccount(alias);
        expect(await rebuilt.agenda.unsyncedCount(), clearing ? 1 : 3);
        expect(
          await rebuilt.agenda.get(original.id),
          clearing ? isNull : isNotNull,
        );
        expect((await rebuilt.agenda.get(fresh.id))!.content.title, '新代次记录');
        await rebuilt.agenda.openAccount(other);
        expect(await rebuilt.agenda.unsyncedCount(), 0);
        await rebuilt.agenda.openAccount(alias);
        expect(await rebuilt.agenda.unsyncedCount(), clearing ? 1 : 3);
      } finally {
        await rebuilt.dispose();
      }
      expect(closedBeforeRelease, isFalse, reason: '关闭必须等待已交付写入收尾');
      expect(gate.clears, clearing ? 1 : 0);
    } finally {
      if (!gate.release.isCompleted) gate.release.complete();
      await agenda.dispose();
      if (!disposed) await backend.dispose();
    }
  }
}

class _GatedBackend implements AgendaBackend {
  _GatedBackend(this.delegate, this.clearing);
  final AgendaService delegate;
  final bool clearing;
  final started = Completer<void>();
  final release = Completer<void>();
  int clears = 0;
  Future<void> _pause() async {
    if (started.isCompleted) return;
    started.complete();
    await release.future;
  }

  @override
  Future<void> openAccount(String accountId) => delegate.openAccount(accountId);
  @override
  Future<void> deactivate() => delegate.close();
  @override
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) async {
    if (!clearing) await _pause();
    return delegate.create(draft, now);
  }

  @override
  Future<int> clearLocalData() async {
    clears++;
    if (clearing) await _pause();
    return delegate.clearLocalData();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
