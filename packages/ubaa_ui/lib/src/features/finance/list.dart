part of 'view.dart';

/// 一个所属年月下的记录；所属年月缺失时归入“其他”，只在“全部”中显示。
final class _FinanceGroup {
  const _FinanceGroup(this.year, this.month, this.entries);
  final String year;
  final int month;
  final List<FinanceIncome> entries;

  bool get known => year.isNotEmpty;

  _FinanceGroup where(String keyword) => keyword.isEmpty
      ? this
      : _FinanceGroup(year, month, [
          for (final e in entries)
            if ([
              e.project,
              e.description,
              e.id,
            ].any((v) => v?.toLowerCase().contains(keyword) ?? false))
              e,
        ]);
}

/// 按财务系统的所属年月分组，组内按录入日期倒序；上游返回顺序不作保证。
final class _FinancePeriods {
  const _FinancePeriods(this.groups, this.years);
  final List<_FinanceGroup> groups;
  final List<String> years;

  /// 优先使用所属年月，缺失或无效时退回录入日期的年月。
  static (int, int)? periodOf(FinanceIncome e) {
    final year = int.tryParse(e.year?.trim() ?? '');
    final month = int.tryParse(e.month?.trim() ?? '');
    if (year != null && month != null && month >= 1 && month <= 12) {
      return (year, month);
    }
    final date = _parseDate(e.recordedDate);
    return date == null ? null : (date.year, date.month);
  }

  static _FinancePeriods of(List<FinanceIncome> entries) {
    final buckets = <(int, int), List<FinanceIncome>>{};
    final other = <FinanceIncome>[];
    for (final e in entries) {
      final period = periodOf(e);
      if (period == null) {
        other.add(e);
      } else {
        (buckets[period] ??= []).add(e);
      }
    }
    int byDate(FinanceIncome a, FinanceIncome b) {
      final date = (b.recordedDate ?? '').compareTo(a.recordedDate ?? '');
      return date != 0 ? date : a.id.compareTo(b.id);
    }

    final keys = buckets.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : b.$2 - a.$2);
    final groups = [
      for (final key in keys)
        _FinanceGroup('${key.$1}', key.$2, buckets[key]!..sort(byDate)),
      if (other.isNotEmpty) _FinanceGroup('', 0, other..sort(byDate)),
    ];
    final years = <String>[
      for (final key in keys) '${key.$1}',
    ].toSet().toList();
    return _FinancePeriods(groups, years);
  }
}

int _sum(Iterable<int?> values) =>
    values.fold(0, (total, value) => total + (value ?? 0));

/// 当前范围的实发合计，次要行列出笔数、应发与扣税。
class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.label, required this.entries});
  final String label;
  final List<FinanceIncome> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tax = _sum(entries.map((e) => e.taxCents));
    final missing = entries.where((e) => e.paidCents == null).length;
    final details = [
      '共 ${entries.length} 笔',
      '应发 ${financeYuan(_sum(entries.map((e) => e.amountCents)))}',
      if (tax != 0) '扣税 ${financeYuan(tax)}',
    ];
    final onCard = scheme.onPrimaryContainer;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: onCard,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: onCard),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                financeYuan(_sum(entries.map((e) => e.paidCents))),
                maxLines: 1,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: onCard,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              details.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: onCard.withValues(alpha: 0.8),
              ),
            ),
            if (missing > 0) ...[
              const SizedBox(height: 2),
              Text(
                '其中 $missing 笔未提供实发金额，未计入合计',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onCard.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 月份标题带当月实发小计，记录在同一张卡片内以分隔线排列。
class _FinanceMonth extends StatelessWidget {
  const _FinanceMonth({
    super.key,
    required this.group,
    required this.showYear,
    required this.onOpen,
  });
  final _FinanceGroup group;
  final bool showYear;
  final ValueChanged<FinanceIncome> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = !group.known
        ? '其他'
        : showYear
        ? '${group.year}年${group.month}月'
        : '${group.month}月';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '实发 ${financeYuan(_sum(group.entries.map((e) => e.paidCents)))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, entry) in group.entries.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  _FinanceRow(entry: entry, onTap: () => onOpen(entry)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({required this.entry, required this.onTap});
  final FinanceIncome entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final subtitle = _subtitle(entry);
    final date = _parseDate(entry.recordedDate);
    final tax = entry.taxCents;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(entry),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                    ],
                    if (date != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${uiDay(date, now: uiCampusNow())}录入',
                        style: secondary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    financeYuan(entry.paidCents),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (tax != null && tax != 0) ...[
                    const SizedBox(height: 2),
                    Text('扣税 ${financeYuan(tax)}', style: secondary),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情顶部的实发金额，与列表右侧同一口径。
class _FinanceHeadline extends StatelessWidget {
  const _FinanceHeadline({required this.entry});
  final FinanceIncome entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '实发',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            financeYuan(entry.paidCents),
            maxLines: 1,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
