import '../common/route.dart';

/// 财务收入展示字段；金额单位为分，缺失值与零值分别保留。
final class FinanceIncome {
  const FinanceIncome({
    required this.id,
    this.project,
    this.description,
    this.amountCents,
    this.taxCents,
    this.paidCents,
    this.taxRate,
    this.recordedDate,
    this.year,
    this.month,
  });
  final String id;
  final String? project, description, taxRate, recordedDate, year, month;
  final int? amountCents, taxCents, paidCents;
}

/// 本次接口范围的完整记录及来源时间，不推断银行到账。
final class FinanceSnapshot {
  FinanceSnapshot({
    required List<FinanceIncome> entries,
    required this.total,
    required this.route,
    required this.fetchedAt,
    required this.fromCache,
    required this.savedForOffline,
    this.saveError,
  }) : entries = List.unmodifiable(entries);
  final List<FinanceIncome> entries;
  final int total;
  final ConnectionMode route;
  final DateTime fetchedAt;
  final bool fromCache, savedForOffline;
  final String? saveError;
}

abstract interface class FinanceService {
  Future<FinanceSnapshot?> cached();
  Future<FinanceSnapshot> refresh();
}
