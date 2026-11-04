import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';

class MemoryAgenda
    implements AgendaBackend, AgendaDraftBackend, AgendaExportBackend {
  final items = <String, AgendaItem>{};
  final overlays = <String, AgendaOverlay>{};
  Completer<AgendaQueryResult>? gate;
  Completer<AgendaExportResult>? exportGate;
  bool? exportedCompleted;
  int writes = 0;
  AgendaEditScope? lastEdit, lastDelete;
  bool failWrite = false;
  final school = <SchoolAgendaItem>[];
  final sources = <AgendaSource>[];
  AgendaQuery? lastQuery;
  @override
  Future<AgendaQueryResult> query(AgendaQuery q) async {
    lastQuery = q;
    if (gate != null) return gate!.future;
    return AgendaQueryResult(
      entries: [
        for (final value in school)
          if (q.includeHidden ||
              overlays[value.key.upstreamId]?.value.hidden != true)
            AgendaEntry(
              school: value,
              timing: value.timing,
              sortTime: value.sortTime,
              soon: false,
              completed:
                  overlays[value.key.upstreamId]?.value.completedAt != null,
              hidden: overlays[value.key.upstreamId]?.value.hidden ?? false,
              note: overlays[value.key.upstreamId]?.value.note,
            ),
        for (final item in items.values)
          if (item.deletedAt == null)
            AgendaEntry(
              local: AgendaOccurrence(
                itemId: item.id,
                recurrenceId:
                    item.content.start?.rfc3339 ??
                    item.content.due?.rfc3339 ??
                    'undated',
                content: item.content,
                completedAt: item.completions.firstOrNull?.completedAt,
                overridden: false,
              ),
              timing: AgendaTiming(
                kind: item.content.kind == AgendaKind.task
                    ? (item.content.due == null
                          ? AgendaTimingKind.undated
                          : AgendaTimingKind.deadline)
                    : (item.content.allDay
                          ? AgendaTimingKind.allDay
                          : AgendaTimingKind.period),
                from: item.content.allDay
                    ? item.content.start?.rfc3339.substring(0, 10)
                    : null,
                to: item.content.allDay
                    ? item.content.end?.rfc3339.substring(0, 10)
                    : null,
                start: item.content.start,
                end: item.content.end,
                due: item.content.due,
              ),
              sortTime: item.content.start ?? item.content.due,
              soon: false,
              completed: item.completions.firstOrNull?.completedAt != null,
              hidden: false,
            ),
      ],
      sources: sources,
    );
  }

  @override
  Future<AgendaItem> create(AgendaDraft d, AgendaTime now) async {
    if (failWrite) throw const AgendaException(AgendaFailure.unavailable);
    writes++;
    final item = AgendaItem(
      id: '${items.length}',
      content: d.content,
      rrule: d.rrule,
      exdates: d.exdates,
      overrides: [],
      completions: [],
      createdAt: now,
      updatedAt: now,
      locallyModified: true,
    );
    items[item.id] = item;
    return item;
  }

  @override
  Future<AgendaItem?> get(String id) async => items[id];
  @override
  Future<String?> edit(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  ) => editDraft(
    id,
    scope,
    at,
    AgendaDraft(content: content, rrule: rrule, exdates: items[id]!.exdates),
    now,
  );
  @override
  Future<String?> editDraft(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaDraft draft,
    AgendaTime now,
  ) async {
    if (failWrite) throw const AgendaException(AgendaFailure.unavailable);
    lastEdit = scope;
    writes++;
    items[id] = AgendaItem(
      id: id,
      content: draft.content,
      rrule: draft.rrule,
      exdates: draft.exdates,
      overrides: [],
      completions: [],
      createdAt: items[id]!.createdAt,
      updatedAt: now,
      locallyModified: true,
    );
    return null;
  }

  @override
  Future<void> delete(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  ) async {
    lastDelete = scope;
    writes++;
    items.remove(id);
  }

  @override
  Future<void> complete(
    String id,
    AgendaTime? at,
    bool done,
    AgendaTime now,
  ) async {
    final item = items[id]!;
    items[id] = AgendaItem(
      id: id,
      content: item.content,
      rrule: item.rrule,
      exdates: item.exdates,
      overrides: [],
      completions: [
        AgendaCompletion(
          recurrenceId: at?.rfc3339 ?? 'undated',
          completedAt: done ? now : null,
        ),
      ],
      createdAt: item.createdAt,
      updatedAt: now,
      locallyModified: true,
    );
  }

  @override
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key) async =>
      overlays[key.upstreamId];
  @override
  Future<void> setOverlay(AgendaOverlayDraft draft, AgendaTime now) async {
    overlays[draft.key.upstreamId] = AgendaOverlay(
      value: draft,
      updatedAt: now,
      locallyModified: true,
    );
  }

  @override
  Future<AgendaExportResult> exportIcs(
    AgendaQuery query,
    bool includeCompleted,
  ) async {
    lastQuery = query;
    exportedCompleted = includeCompleted;
    if (exportGate != null) return exportGate!.future;
    return const AgendaExportResult(
      ics: 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
      exportedCount: 1,
      skippedUnknownTimeCount: 0,
    );
  }

  @override
  Future<void> openAccount(String id) async {}
  @override
  Future<void> deactivate() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
