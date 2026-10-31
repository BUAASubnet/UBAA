/// 本机日程的不可变领域值，不携带学校操作资格。
library;

enum AgendaFailure {
  unavailable,
  invalidInput,
  corrupt,
  unsupportedVersion,
  inactive,
  superseded,
  capacity,
}

final class AgendaTime {
  AgendaTime({required this.rfc3339, required this.timezone});
  final String rfc3339;
  final String timezone;
}

enum AgendaKind { event, task }

final class AgendaContent {
  AgendaContent({
    required this.kind,
    required this.title,
    this.location,
    this.notes,
    this.color,
    this.start,
    this.end,
    required this.allDay,
    this.due,
  });
  final AgendaKind kind;
  final String title;
  final String? location;
  final String? notes;
  final String? color;
  final AgendaTime? start;
  final AgendaTime? end;
  final bool allDay;
  final AgendaTime? due;
}

final class AgendaDraft {
  AgendaDraft({
    required this.content,
    this.rrule,
    required List<AgendaTime> exdates,
  }) : exdates = List.unmodifiable(exdates);
  final AgendaContent content;
  final String? rrule;
  final List<AgendaTime> exdates;
}

final class AgendaOverride {
  AgendaOverride({required this.recurrenceId, required this.content});
  final String recurrenceId;
  final AgendaContent content;
}

final class AgendaCompletion {
  AgendaCompletion({required this.recurrenceId, this.completedAt});
  final String recurrenceId;
  final AgendaTime? completedAt;
}

final class AgendaItem {
  AgendaItem({
    required this.id,
    required this.content,
    this.rrule,
    required List<AgendaTime> exdates,
    required List<AgendaOverride> overrides,
    required List<AgendaCompletion> completions,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.locallyModified,
  }) : exdates = List.unmodifiable(exdates),
       overrides = List.unmodifiable(overrides),
       completions = List.unmodifiable(completions);
  final String id;
  final AgendaContent content;
  final String? rrule;
  final List<AgendaTime> exdates;
  final List<AgendaOverride> overrides;
  final List<AgendaCompletion> completions;
  final AgendaTime createdAt;
  final AgendaTime updatedAt;
  final AgendaTime? deletedAt;
  final bool locallyModified;
}

final class AgendaOccurrence {
  AgendaOccurrence({
    required this.itemId,
    required this.recurrenceId,
    required this.content,
    this.completedAt,
    required this.overridden,
  });
  final String itemId;
  final String recurrenceId;
  final AgendaContent content;
  final AgendaTime? completedAt;
  final bool overridden;
}

enum AgendaEditScope { thisOccurrence, thisAndFuture, all }

final class SchoolAgendaKey {
  SchoolAgendaKey({required this.source, required this.upstreamId});
  final String source;
  final String upstreamId;
}

final class AgendaOverlayDraft {
  AgendaOverlayDraft({
    required this.key,
    this.completedAt,
    required this.completionOverride,
    required this.hidden,
    this.note,
  });
  final SchoolAgendaKey key;
  final AgendaTime? completedAt;
  final bool completionOverride;
  final bool hidden;
  final String? note;
}

final class AgendaOverlay {
  AgendaOverlay({
    required this.value,
    required this.updatedAt,
    this.deletedAt,
    required this.locallyModified,
  });
  final AgendaOverlayDraft value;
  final AgendaTime updatedAt;
  final AgendaTime? deletedAt;
  final bool locallyModified;
}

enum TeachingWeekPattern { every, odd, even }

final class TeachingWeekInput {
  TeachingWeekInput({
    required this.monday,
    required this.first,
    required this.last,
    required this.pattern,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.second,
    required List<String> skips,
  }) : skips = List.unmodifiable(skips);
  final String monday;
  final int first;
  final int last;
  final TeachingWeekPattern pattern;
  final int weekday;
  final int hour;
  final int minute;
  final int second;
  final List<String> skips;
}

final class TeachingWeekRule {
  TeachingWeekRule({
    required this.start,
    required this.rrule,
    required List<AgendaTime> exdates,
  }) : exdates = List.unmodifiable(exdates);
  final AgendaTime start;
  final String rrule;
  final List<AgendaTime> exdates;
}
