import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/chip_strip.dart';
import '../../common/detail_fields.dart';
import '../../common/search_field.dart';
import '../../common/state_panel.dart';
import '../../shared/dialogs/sheet.dart';
import '../../shared/loading.dart';
import '../../shared/refresh.dart';
import '../../shared/sync_status.dart' show uiIsTouchPlatform;
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart' show uiClock, uiDay, uiCampusNow;
import '../../theme.dart';
part 'list.dart';

/// 金额以整数分保存，显示时补千分位与两位小数；缺失显示破折号，零值照常显示。
String financeYuan(int? cents) {
  if (cents == null) return '—';
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  final fraction = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}¥$whole.$fraction';
}

const _noBankNote = '记录来自学校财务查询系统的录入信息，到账以银行为准。';

/// 财务收入独立页面：先显示本机离线记录，再读取完整在线结果。
///
/// 只读页面，不参与首页后台刷新；账号或路线变化时由外层更换 [service]。
class FinanceView extends StatefulWidget {
  const FinanceView({
    required this.service,
    this.scopeKey,
    this.connecting = false,
    super.key,
  });
  final FinanceService? service;
  final Object? scopeKey;
  final bool connecting;
  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  static const _all = '';
  final _search = TextEditingController();
  FinanceSnapshot? _snapshot;
  bool _loading = false;
  String? _error;
  String _keyword = '';

  /// 用户选择的年份；为空时跟随最近一年，[_all] 表示全部年份。
  String? _year;
  int _revision = 0;
  Future<void>? _pending;

  @override
  void initState() {
    super.initState();
    unawaited(_load(withCache: true));
  }

  @override
  void didUpdateWidget(covariant FinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        oldWidget.scopeKey != widget.scopeKey ||
        (oldWidget.connecting && !widget.connecting)) {
      final sameAccount =
          widget.scopeKey != null && oldWidget.scopeKey == widget.scopeKey;
      _revision++;
      _pending = null;
      if (!sameAccount) _snapshot = null;
      _error = null;
      if (!sameAccount) _year = null;
      _loading = false;
      unawaited(_load(withCache: !sameAccount || _snapshot == null));
    }
  }

  @override
  void dispose() {
    _revision++;
    _search.dispose();
    super.dispose();
  }

  /// 下拉、按钮与重试加入同一次进行中的读取。
  Future<void> _load({bool withCache = false}) {
    if (_pending case final pending?) return pending;
    late final Future<void> read;
    read = _fetch(withCache).whenComplete(() {
      if (identical(_pending, read)) _pending = null;
    });
    return _pending = read;
  }

  Future<void> _fetch(bool withCache) async {
    final service = widget.service;
    if (service == null || (widget.connecting && !withCache)) return;
    final revision = ++_revision;
    bool current() => mounted && revision == _revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (withCache) {
      try {
        final cached = await service.cached();
        if (!current()) return;
        if (cached != null && _snapshot == null) {
          setState(() => _snapshot = cached);
        }
      } on Object {
        // 离线记录读取失败不影响在线读取，也不单独提示。
        if (!current()) return;
      }
    }
    if (widget.connecting) {
      if (current()) setState(() => _loading = false);
      return;
    }
    try {
      final fresh = await service.refresh();
      if (!current()) return;
      setState(() => _snapshot = fresh);
    } on Object catch (error) {
      if (!current()) return;
      setState(() => _error = error is UiError ? error.message : '读取失败，请稍后重试');
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.service == null) {
      return const UiStatePanel(
        icon: Icons.block_outlined,
        title: '此版本暂不支持财务查询',
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return PullToRefresh(
        onRefresh: _load,
        child: RefreshViewport(
          child: _error != null
              ? UiStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: '财务记录读取失败',
                  detail: _error,
                  action: '重试',
                  actionIcon: Icons.refresh,
                  onAction: _load,
                )
              : const LoadingPlaceholder(),
        ),
      );
    }
    final periods = _FinancePeriods.of(snapshot.entries);
    final years = periods.years;
    final year = switch (_year) {
      null => years.firstOrNull ?? _all,
      final picked when picked == _all || years.contains(picked) => picked,
      _ => years.firstOrNull ?? _all,
    };
    final keyword = _keyword.trim().toLowerCase();
    final groups = periods.groups
        .where((g) => year == _all || g.year == year)
        .map((g) => g.where(keyword))
        .where((g) => g.entries.isNotEmpty)
        .toList();
    final visible = [for (final g in groups) ...g.entries];
    final desktop = !uiIsTouchPlatform(context);
    return PullToRefresh(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey<String>('finance-page'),
        padding: UbaaTheme.pageInsets(context, top: 8),
        children: [
          Row(
            children: [
              Expanded(
                child: UiSearchField(
                  controller: _search,
                  hintText: '搜索项目或摘要',
                  onChanged: (value) => setState(() => _keyword = value),
                ),
              ),
              if (desktop) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const LoadingGlyph()
                      : const Icon(Icons.refresh),
                ),
              ],
            ],
          ),
          if (years.length > 1) ...[
            const SizedBox(height: 12),
            UiChipStrip(
              spacing: 8,
              bleed: true,
              children: [
                for (final option in [...years, _all])
                  ChoiceChip(
                    label: Text(option == _all ? '全部' : '$option年'),
                    selected: year == option,
                    onSelected: (_) => setState(() => _year = option),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            UiInlineRetry(
              message: '刷新失败：$_error。以下为上次的记录',
              onRetry: _loading ? null : _load,
            ),
          ],
          const SizedBox(height: 12),
          _FinanceSummary(
            label: keyword.isNotEmpty
                ? '搜索结果实发合计'
                : year == _all
                ? '全部实发合计'
                : '$year年实发合计',
            entries: visible,
          ),
          const SizedBox(height: 16),
          if (snapshot.entries.isEmpty)
            const UiStatePanel(
              compact: true,
              icon: Icons.receipt_long_outlined,
              title: '暂无收入记录',
              detail: '财务系统当前没有返回本人的收入记录',
            )
          else if (visible.isEmpty)
            const UiStatePanel(
              compact: true,
              icon: Icons.search_off_outlined,
              title: '没有匹配的记录',
            )
          else
            for (final group in groups)
              _FinanceMonth(
                key: ValueKey('finance-${group.year}-${group.month}'),
                group: group,
                showYear: year == _all,
                onOpen: (entry) => _openDetail(context, entry),
              ),
          const SizedBox(height: 8),
          _FinanceFooter(snapshot: snapshot, refreshing: _loading),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, FinanceIncome entry) {
    final period = _FinancePeriods.periodOf(entry);
    final date = _parseDate(entry.recordedDate);
    unawaited(
      showUiSheet<void>(
        context,
        builder: (context) => UiSheetBody(
          title: _title(entry),
          subtitle: _subtitle(entry),
          children: [
            _FinanceHeadline(entry: entry),
            const SizedBox(height: 12),
            DetailField(label: '应发金额', value: financeYuan(entry.amountCents)),
            DetailField(label: '扣税', value: financeYuan(entry.taxCents)),
            DetailField(label: '实发金额', value: financeYuan(entry.paidCents)),
            DetailField(label: '税率', value: uiNonBlank(entry.taxRate) ?? '—'),
            if (period != null)
              DetailField(label: '所属年月', value: '${period.$1}年${period.$2}月'),
            DetailField(
              label: '录入日期',
              value: date == null
                  ? uiNonBlank(entry.recordedDate) ?? '—'
                  : '${date.year}年${date.month}月${date.day}日',
            ),
            DetailField(label: '流水号', value: entry.id),
            const SizedBox(height: 12),
            const UiInfoRow(icon: Icons.info_outline, text: _noBankNote),
          ],
        ),
      ),
    );
  }
}

String _title(FinanceIncome e) =>
    uiNonBlank(e.project) ?? uiNonBlank(e.description) ?? '收入记录';

/// 项目名之外的摘要；没有项目名时摘要已作为标题，不再重复。
String? _subtitle(FinanceIncome e) =>
    uiNonBlank(e.project) == null ? null : uiNonBlank(e.description);

final _datePattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');
DateTime? _parseDate(String? raw) {
  final m = _datePattern.firstMatch(raw?.trim() ?? '');
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

class _FinanceFooter extends StatelessWidget {
  const _FinanceFooter({required this.snapshot, required this.refreshing});
  final FinanceSnapshot snapshot;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final at = homeCampusTime(snapshot.fetchedAt);
    final time = '${uiDay(at, now: uiCampusNow())} ${uiClock(at)}';
    final status = snapshot.fromCache
        ? refreshing
              ? '离线记录（$time），正在更新'
              : '离线记录，更新于 $time'
        : '更新于 $time';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$status · 共 ${snapshot.entries.length} 条', style: style),
          if (snapshot.saveError == 'capacity') ...[
            const SizedBox(height: 4),
            Text(
              '手机存储空间不足，本次内容未能保存。',
              style: style?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 4),
          Text(_noBankNote, style: style),
        ],
      ),
    );
  }
}
