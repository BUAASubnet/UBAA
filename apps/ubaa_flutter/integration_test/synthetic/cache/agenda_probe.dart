import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 在真实 FFI 上验证独立日程句柄和生产适配器，全部数据为合成值。
Future<void> probeAgenda(String directory) async {
  const alias = '00000000000000000000000000000003';
  final backend = await BridgeBackend.open(directory);
  final agenda = backend.agenda;
  AgendaTime time(String value) =>
      AgendaTime(rfc3339: value, timezone: 'Asia/Shanghai');
  final now = time('2026-03-24T12:00:00+08:00');
  AgendaQuery query(ConnectionMode route, {String term = 'synthetic'}) =>
      AgendaQuery(
        route: route,
        term: term,
        from: '2026-03-24',
        to: '2026-03-30',
        now: now,
        includeHidden: false,
        ygdkEnabled: true,
        ygdkWeekDone: false,
        ygdkTermDone: false,
      );
  try {
    await agenda.openAccount(alias);
    final item = await agenda.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '合成全天事项',
          start: time('2026-03-24T00:00:00+08:00'),
          end: time('2026-03-25T00:00:00+08:00'),
          allDay: true,
        ),
        exdates: [],
      ),
      now,
    );
    final original = await agenda.get(item.id);
    expect(original!.content.allDay, isTrue);
    expect(original.content.start!.timezone, 'Asia/Shanghai');
    await agenda.complete(item.id, original.content.start, true, now);
    final result = await agenda.query(query(ConnectionMode.direct));
    expect(result.entries.single.completed, isTrue);
    expect(result.entries.single.timing.kind, AgendaTimingKind.allDay);
    expect(result.sources, hasLength(8));
    expect(result.sources.every((s) => s.observations.isEmpty), isTrue);
    final key = SchoolAgendaKey(
      source: 'judge',
      upstreamId: 'synthetic-detail',
    );
    await agenda.setOverlay(
      AgendaOverlayDraft(
        key: key,
        completionOverride: true,
        hidden: true,
        note: '本机备注',
      ),
      now,
    );
    expect((await agenda.overlay(key))!.value.completionOverride, isTrue);
    await expectLater(
      agenda.get('bad-uuid'),
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '稳定输入错误',
          AgendaFailure.invalidInput,
        ),
      ),
    );
    // 未打开缓存不能宣称完成清理，且日程仍可读取。
    await expectLater(
      backend.clearOfflineAccount(accountId: alias),
      throwsA(isA<BackendException>()),
    );
    await backend.openOfflineAccount(
      const LocalAccount(id: alias, username: 'synthetic'),
      List.filled(32, 9),
    );
    for (final route in ConnectionMode.values) {
      final localQuery = query(route, term: '');
      expect(
        (await agenda.query(localQuery)).entries.single.local!.itemId,
        item.id,
      );
      final file = await agenda.exportIcs(localQuery, includeCompleted: true);
      expect(file.exportedCount, 1);
      expect(file.ics, contains('SUMMARY:合成全天事项'));
    }
    await backend.clearBusinessCache(accountId: alias);
    expect((await agenda.get(item.id))!.content.title, '合成全天事项');
    await backend.clearOrRebuildBusinessCache(
      account: const LocalAccount(id: alias, username: 'synthetic'),
      key: List.filled(32, 9),
    );
    expect(
      (await agenda.query(query(ConnectionMode.webvpn)))
          .entries
          .single
          .completed,
      isTrue,
    );
    await agenda.close();
    await expectLater(agenda.get(item.id), throwsA(isA<AgendaException>()));
    await agenda.openAccount(alias);
    expect((await agenda.get(item.id))!.id, item.id);
    expect(await agenda.clearLocalData(), 2);
  } finally {
    await backend.dispose();
  }
}
