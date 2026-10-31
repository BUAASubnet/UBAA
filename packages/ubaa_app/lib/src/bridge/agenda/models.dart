import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/mapping.dart' show bridgeToConnectionMode;

AgendaTime fromAgendaTime(BridgeAgendaTime v) =>
    AgendaTime(rfc3339: v.rfc3339, timezone: v.timezone);
BridgeAgendaTime toAgendaTime(AgendaTime v) =>
    BridgeAgendaTime(rfc3339: v.rfc3339, timezone: v.timezone);
AgendaKind fromAgendaKind(BridgeAgendaKind v) => switch (v) {
  BridgeAgendaKind.event => AgendaKind.event,
  BridgeAgendaKind.task => AgendaKind.task,
};
BridgeAgendaKind toAgendaKind(AgendaKind v) => switch (v) {
  AgendaKind.event => BridgeAgendaKind.event,
  AgendaKind.task => BridgeAgendaKind.task,
};
AgendaContent fromAgendaContent(BridgeAgendaContent v) => AgendaContent(
  kind: fromAgendaKind(v.kind),
  title: v.title,
  location: v.location,
  notes: v.notes,
  color: v.color,
  start: v.start == null ? null : fromAgendaTime(v.start!),
  end: v.end == null ? null : fromAgendaTime(v.end!),
  allDay: v.allDay,
  due: v.due == null ? null : fromAgendaTime(v.due!),
);
BridgeAgendaContent toAgendaContent(AgendaContent v) => BridgeAgendaContent(
  kind: toAgendaKind(v.kind),
  title: v.title,
  location: v.location,
  notes: v.notes,
  color: v.color,
  start: v.start == null ? null : toAgendaTime(v.start!),
  end: v.end == null ? null : toAgendaTime(v.end!),
  allDay: v.allDay,
  due: v.due == null ? null : toAgendaTime(v.due!),
);
AgendaDraft fromAgendaDraft(BridgeAgendaDraft v) => AgendaDraft(
  content: fromAgendaContent(v.content),
  rrule: v.rrule,
  exdates: v.exdates.map((v) => fromAgendaTime(v)).toList(),
);
BridgeAgendaDraft toAgendaDraft(AgendaDraft v) => BridgeAgendaDraft(
  content: toAgendaContent(v.content),
  rrule: v.rrule,
  exdates: v.exdates.map((v) => toAgendaTime(v)).toList(),
);
AgendaOverride fromAgendaOverride(BridgeAgendaOverride v) => AgendaOverride(
  recurrenceId: v.recurrenceId,
  content: fromAgendaContent(v.content),
);
AgendaCompletion fromAgendaCompletion(BridgeAgendaCompletion v) =>
    AgendaCompletion(
      recurrenceId: v.recurrenceId,
      completedAt: v.completedAt == null
          ? null
          : fromAgendaTime(v.completedAt!),
    );
AgendaItem fromAgendaItem(BridgeAgendaItem v) => AgendaItem(
  id: v.id,
  content: fromAgendaContent(v.content),
  rrule: v.rrule,
  exdates: v.exdates.map((v) => fromAgendaTime(v)).toList(),
  overrides: v.overrides.map((v) => fromAgendaOverride(v)).toList(),
  completions: v.completions.map((v) => fromAgendaCompletion(v)).toList(),
  createdAt: fromAgendaTime(v.createdAt),
  updatedAt: fromAgendaTime(v.updatedAt),
  deletedAt: v.deletedAt == null ? null : fromAgendaTime(v.deletedAt!),
  locallyModified: v.locallyModified,
);
AgendaOccurrence fromAgendaOccurrence(BridgeAgendaOccurrence v) =>
    AgendaOccurrence(
      itemId: v.itemId,
      recurrenceId: v.recurrenceId,
      content: fromAgendaContent(v.content),
      completedAt: v.completedAt == null
          ? null
          : fromAgendaTime(v.completedAt!),
      overridden: v.overridden,
    );
AgendaEditScope fromAgendaEditScope(BridgeAgendaEditScope v) => switch (v) {
  BridgeAgendaEditScope.this_ => AgendaEditScope.thisOccurrence,
  BridgeAgendaEditScope.thisAndFuture => AgendaEditScope.thisAndFuture,
  BridgeAgendaEditScope.all => AgendaEditScope.all,
};
BridgeAgendaEditScope toAgendaEditScope(AgendaEditScope v) => switch (v) {
  AgendaEditScope.thisOccurrence => BridgeAgendaEditScope.this_,
  AgendaEditScope.thisAndFuture => BridgeAgendaEditScope.thisAndFuture,
  AgendaEditScope.all => BridgeAgendaEditScope.all,
};
SchoolAgendaKey fromSchoolAgendaKey(BridgeSchoolAgendaKey v) =>
    SchoolAgendaKey(source: v.source, upstreamId: v.upstreamId);
BridgeSchoolAgendaKey toSchoolAgendaKey(SchoolAgendaKey v) =>
    BridgeSchoolAgendaKey(source: v.source, upstreamId: v.upstreamId);
AgendaOverlayDraft fromAgendaOverlayDraft(BridgeAgendaOverlayDraft v) =>
    AgendaOverlayDraft(
      key: fromSchoolAgendaKey(v.key),
      completedAt: v.completedAt == null
          ? null
          : fromAgendaTime(v.completedAt!),
      completionOverride: v.completionOverride,
      hidden: v.hidden,
      note: v.note,
    );
BridgeAgendaOverlayDraft toAgendaOverlayDraft(AgendaOverlayDraft v) =>
    BridgeAgendaOverlayDraft(
      key: toSchoolAgendaKey(v.key),
      completedAt: v.completedAt == null ? null : toAgendaTime(v.completedAt!),
      completionOverride: v.completionOverride,
      hidden: v.hidden,
      note: v.note,
    );
AgendaOverlay fromAgendaOverlay(BridgeAgendaOverlay v) => AgendaOverlay(
  value: fromAgendaOverlayDraft(v.value),
  updatedAt: fromAgendaTime(v.updatedAt),
  deletedAt: v.deletedAt == null ? null : fromAgendaTime(v.deletedAt!),
  locallyModified: v.locallyModified,
);
TeachingWeekPattern fromTeachingWeekPattern(BridgeTeachingWeekPattern v) =>
    switch (v) {
      BridgeTeachingWeekPattern.every => TeachingWeekPattern.every,
      BridgeTeachingWeekPattern.odd => TeachingWeekPattern.odd,
      BridgeTeachingWeekPattern.even => TeachingWeekPattern.even,
    };
BridgeTeachingWeekPattern toTeachingWeekPattern(TeachingWeekPattern v) =>
    switch (v) {
      TeachingWeekPattern.every => BridgeTeachingWeekPattern.every,
      TeachingWeekPattern.odd => BridgeTeachingWeekPattern.odd,
      TeachingWeekPattern.even => BridgeTeachingWeekPattern.even,
    };
TeachingWeekInput fromTeachingWeekInput(BridgeTeachingWeekInput v) =>
    TeachingWeekInput(
      monday: v.monday,
      first: v.first,
      last: v.last,
      pattern: fromTeachingWeekPattern(v.pattern),
      weekday: v.weekday,
      hour: v.hour,
      minute: v.minute,
      second: v.second,
      skips: v.skips.map((v) => v).toList(),
    );
BridgeTeachingWeekInput toTeachingWeekInput(TeachingWeekInput v) =>
    BridgeTeachingWeekInput(
      monday: v.monday,
      first: v.first,
      last: v.last,
      pattern: toTeachingWeekPattern(v.pattern),
      weekday: v.weekday,
      hour: v.hour,
      minute: v.minute,
      second: v.second,
      skips: v.skips.map((v) => v).toList(),
    );
TeachingWeekRule fromTeachingWeekRule(BridgeTeachingWeekRule v) =>
    TeachingWeekRule(
      start: fromAgendaTime(v.start),
      rrule: v.rrule,
      exdates: v.exdates.map((v) => fromAgendaTime(v)).toList(),
    );
ConnectionMode fromConnectionMode(BridgeConnectionMode v) =>
    bridgeToConnectionMode(v);
BridgeConnectionMode toConnectionMode(ConnectionMode v) => switch (v) {
  ConnectionMode.direct => BridgeConnectionMode.direct,
  ConnectionMode.webvpn => BridgeConnectionMode.webVpn,
};
CacheMaintenanceFailure fromCacheFailure(BridgeCacheFailure v) => switch (v) {
  BridgeCacheFailure.unavailable => CacheMaintenanceFailure.unavailable,
  BridgeCacheFailure.invalidInput => CacheMaintenanceFailure.invalidInput,
  BridgeCacheFailure.corrupt => CacheMaintenanceFailure.corrupt,
  BridgeCacheFailure.unsupportedVersion =>
    CacheMaintenanceFailure.unsupportedVersion,
  BridgeCacheFailure.inactive => CacheMaintenanceFailure.inactive,
  BridgeCacheFailure.superseded => CacheMaintenanceFailure.superseded,
  BridgeCacheFailure.capacity => CacheMaintenanceFailure.capacity,
};
BridgeCacheFailure toCacheFailure(CacheMaintenanceFailure v) => switch (v) {
  CacheMaintenanceFailure.unavailable => BridgeCacheFailure.unavailable,
  CacheMaintenanceFailure.invalidInput => BridgeCacheFailure.invalidInput,
  CacheMaintenanceFailure.corrupt => BridgeCacheFailure.corrupt,
  CacheMaintenanceFailure.unsupportedVersion =>
    BridgeCacheFailure.unsupportedVersion,
  CacheMaintenanceFailure.inactive => BridgeCacheFailure.inactive,
  CacheMaintenanceFailure.superseded => BridgeCacheFailure.superseded,
  CacheMaintenanceFailure.capacity => BridgeCacheFailure.capacity,
};
