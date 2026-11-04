import 'school.dart';
import 'models.dart';

/// Core 展开的日期范围快照，不包含完整重复系列。
final class AgendaExportResult {
  const AgendaExportResult({
    required this.ics,
    required this.exportedCount,
    required this.skippedUnknownTimeCount,
  });
  final String ics;
  final int exportedCount;
  final int skippedUnknownTimeCount;
}

abstract interface class AgendaExportBackend {
  Future<AgendaExportResult> exportIcs(
    AgendaQuery query,
    bool includeCompleted,
  );
}

abstract interface class AgendaDraftBackend {
  Future<String?> editDraft(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaDraft draft,
    AgendaTime now,
  );
}
