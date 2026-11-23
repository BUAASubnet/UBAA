import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/state_panel.dart';
import 'package:ubaa_ui/src/common/tag.dart';
import 'package:ubaa_ui/src/shared/feedback.dart';
import 'package:ubaa_ui/src/shared/loading.dart';
import 'package:ubaa_ui/src/shared/refresh.dart';
import 'package:ubaa_ui/src/shared/text.dart' show uiNonBlank;
import 'package:ubaa_ui/src/shared/when.dart' show uiShortDateTime;
import 'package:ubaa_ui/src/theme.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';

/// 当前借阅独立页面：读取当前账号的完整借阅范围，并提供单本续借。
///
/// 页面只消费 facade 投影；账号、路线与写入确认由外层保存和协调。
class LibraryLoansView extends StatefulWidget {
  const LibraryLoansView({
    required this.read,
    this.renew,
    this.pending = const {},
    this.recheck,
    super.key,
  });

  final LibraryLoansReader read;
  final LibraryLoanRenewStarter? renew;
  final Set<String> pending;
  final LibraryLoanRenewStarter? recheck;

  @override
  State<LibraryLoansView> createState() => _LibraryLoansViewState();
}

class _LibraryLoansViewState extends State<LibraryLoansView> {
  List<LibraryLoan>? _loans;
  UiError? _error;
  bool _loading = false;
  int _loadRevision = 0;
  int _readerRevision = 0;
  String? _renewing;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LibraryLoansView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.read != widget.read) {
      _readerRevision++;
      _loans = null;
      _error = null;
      _renewing = null;
      unawaited(_load());
    }
  }

  Future<bool> _load() async {
    final revision = ++_loadRevision;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loans = await widget.read();
      if (!mounted || revision != _loadRevision) return false;
      setState(() {
        _loans = loans;
        _error = null;
        _loading = false;
      });
      return true;
    } on Object catch (error) {
      if (!mounted || revision != _loadRevision) return false;
      setState(() {
        _error = error is UiError
            ? error
            : const UiError(
                code: UbaaErrorCode.upstreamUnavailable,
                title: '借阅记录读取失败',
                message: '读取失败，请稍后重试',
              );
        _loading = false;
      });
      return false;
    }
  }

  Future<void> _refresh() async {
    await _load();
  }

  Future<void> _renew(String loanId, {bool checkOnly = false}) async {
    final renew = checkOnly ? widget.recheck : widget.renew;
    if (renew == null || _renewing != null) return;
    final readerRevision = _readerRevision;
    setState(() => _renewing = loanId);
    WriteOutcome? outcome;
    try {
      outcome = await renew(loanId);
    } finally {
      if (mounted && readerRevision == _readerRevision) {
        final readback = outcome?.libraryLoanRenewReadback;
        setState(() {
          _renewing = null;
          if (readback != null) {
            // 核对结果生效后，忽略仍在途的普通读取及其错误。
            _loadRevision++;
            _loans = readback.loans;
            _error = null;
            _loading = false;
          }
        });
      }
    }
    if (!mounted || readerRevision != _readerRevision || outcome == null) {
      return;
    }
    final readback = outcome.libraryLoanRenewReadback;
    final after = readback?.loans
        .where((value) => value.id == loanId)
        .firstOrNull;
    final unknown =
        outcome.result?.outcomeUnknown == true ||
        outcome.error?.code == UbaaErrorCode.outcomeUnknown;
    if (readback?.verified == true) {
      final dueDate = after?.dueDate;
      final detail = dueDate == null ? '' : '，应还日期 ${uiShortDateTime(dueDate)}';
      UbaaFeedback.show(context, '续借成功$detail', kind: UbaaFeedbackKind.success);
    } else if (unknown && readback?.status == LibraryRenewStatus.unchanged) {
      UbaaFeedback.show(context, '续借未生效，如需再次续借请重新确认');
    } else if (unknown) {
      UbaaFeedback.showWarning(
        context,
        '续借结果未确认，请稍后核对，勿重复提交',
        outcome.error ?? outcome.resultError,
      );
    } else if (outcome.result?.success == true) {
      UbaaFeedback.show(
        context,
        '续借已提交，借阅记录暂未更新',
        kind: UbaaFeedbackKind.warning,
      );
    } else {
      UbaaFeedback.showOutcome(context, outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = _loans;
    if (loans == null && widget.pending.isEmpty) {
      return PullToRefresh(
        onRefresh: _refresh,
        child: RefreshViewport(
          child: _error != null
              ? UiStatePanel(
                  icon: Icons.cloud_off_outlined,
                  // 权限类错误（如当前路线不支持）自带更准确的标题。
                  title: _error!.code == UbaaErrorCode.permissionDenied
                      ? _error!.title
                      : '借阅记录读取失败',
                  detail: _error!.message,
                  action: '重试',
                  actionIcon: Icons.refresh,
                  onAction: _load,
                  error: _error,
                )
              : const LoadingPlaceholder(),
        ),
      );
    }
    final error = _error;
    return PullToRefresh(
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey<String>('library-loans-page'),
        padding: UbaaTheme.pageInsets(context, top: 8),
        children: [
          if (loans != null)
            _Header(total: loans.length, loading: _loading, onRefresh: _load),
          if (error != null) _ErrorBanner(error: error, onRetry: _load),
          for (final id in widget.pending.where(
            (id) => !(loans?.any((loan) => loan.id == id) ?? false),
          ))
            ListTile(
              title: const Text('续借待核对'),
              trailing: TextButton(
                onPressed: _renewing == null && widget.recheck != null
                    ? () => _renew(id, checkOnly: true)
                    : null,
                child: const Text('核对'),
              ),
            ),
          if (loans != null && loans.isEmpty)
            const SizedBox(
              height: 280,
              child: UiStatePanel(
                icon: Icons.menu_book_outlined,
                title: '暂无待还图书',
                detail: '当前账号没有未归还的借阅记录',
              ),
            )
          else if (loans != null) ...[
            for (final loan in loans)
              _LoanCard(
                loan: loan,
                renewing: _renewing == loan.id,
                renewEnabled:
                    widget.renew != null &&
                    _renewing == null &&
                    (loan.canRenewTimes ?? 0) > 0 &&
                    !widget.pending.contains(loan.id),
                pending: widget.pending.contains(loan.id),
                onRecheck: _renewing == null && widget.recheck != null
                    ? () => _renew(loan.id, checkOnly: true)
                    : null,
                onRenew: () => _renew(loan.id),
              ),
            const SizedBox(height: 8),
            const _FooterNote(),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.loading,
    required this.onRefresh,
  });

  final int total;
  final bool loading;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 $total 本在借',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : onRefresh,
            icon: loading ? const LoadingGlyph() : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final UiError error;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: Text(error.title),
      subtitle: Text(error.message),
      trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
    ),
  );
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.renewing,
    required this.renewEnabled,
    required this.onRenew,
    required this.pending,
    required this.onRecheck,
  });

  final LibraryLoan loan;
  final bool renewing;
  final bool renewEnabled;
  final VoidCallback onRenew;
  final bool pending;
  final VoidCallback? onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final author = loan.author;
    final location = loan.location;
    final (statusLabel, statusTone) = switch (loan.status) {
      LibraryLoanStatus.overdue => ('已超期', UiTagTone.error),
      LibraryLoanStatus.soon => ('即将到期', UiTagTone.warning),
      LibraryLoanStatus.normal || LibraryLoanStatus.other => (null, null),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    loan.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (statusLabel != null) ...[
                  const SizedBox(width: 8),
                  UiTag(statusLabel, tone: statusTone!),
                ],
              ],
            ),
            if (author != null && uiNonBlank(author) != null) ...[
              const SizedBox(height: 4),
              Text(
                author,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            _Detail(label: '借阅日期', value: _date(loan.loanDate)),
            _Detail(label: '应还日期', value: _date(loan.dueDate)),
            if (location != null && uiNonBlank(location) != null)
              _Detail(label: '馆藏地', value: location),
            const SizedBox(height: 10),
            // 待核对时续借不可用，主操作换成只读核对，避免同时出现两个入口。
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      UiTag('续借 ${_count(loan.renewTimes)} 次'),
                      UiTag(_renewable(loan.canRenewTimes)),
                      if (pending) const UiTag('待核对', tone: UiTagTone.warning),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (pending)
                  FilledButton.tonalIcon(
                    onPressed: onRecheck,
                    icon: Icon(
                      renewing
                          ? Icons.hourglass_top
                          : Icons.fact_check_outlined,
                      size: 18,
                    ),
                    label: Text(renewing ? '核对中' : '核对'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: renewEnabled ? onRenew : null,
                    icon: Icon(
                      renewing ? Icons.hourglass_top : Icons.autorenew,
                      size: 18,
                    ),
                    label: Text(renewing ? '处理中' : '续借'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _date(String? raw) =>
      raw == null || raw.trim().isEmpty ? '—' : uiShortDateTime(raw);

  static String _count(int? value) => value == null ? '未知' : '$value';

  static String _renewable(int? value) => switch (value) {
    null => '可续借次数未知',
    0 => '不可续借',
    final count => '可续借 $count 次',
  };
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: Text(
      '续借结果与应还日期以学校图书馆记录为准。',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
