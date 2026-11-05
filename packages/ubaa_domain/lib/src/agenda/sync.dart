import 'models.dart';

enum AgendaSyncAction { pull, push, createConfirmed }

enum AgendaSyncStatus {
  upToDate,
  pending,
  needsCreation,
  locationUnknown,
  unverified,
  failed,
  conflict,
  outcomeUnknown,
}

final class AgendaSyncReport {
  const AgendaSyncReport({
    required this.status,
    required this.pendingCount,
    required this.changedCount,
  });
  final AgendaSyncStatus status;
  final int pendingCount;
  final int changedCount;
}

final class AgendaSyncState {
  const AgendaSyncState({
    this.report,
    this.running = false,
    this.error,
    this.localPendingCount,
  });
  final AgendaSyncReport? report;
  final bool running;
  final Object? error;
  final int? localPendingCount;
}

typedef AgendaSyncJob = Future<AgendaSyncReport> Function();

/// 通过共用 Core 服务同步，不从日程领域层构造云盘请求。
abstract interface class AgendaSyncBackend {
  Future<bool> syncEnabled();

  /// 同步捕获创建确认的作用域；返回的作业在确认后才开始。
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now);
}
