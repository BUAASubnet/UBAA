import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'share_form.dart';
import 'write_flow.dart';
import '../../shared/dialogs/scope_boundary.dart';
import '../../shared/dialogs/sheet.dart';
import '../../shared/feedback.dart';
import '../../shared/refresh.dart';
import '../../shared/loading.dart';
import '../../common/state_panel.dart';

/// 有效期的展示文字；过期时第二项为 true。
(String, bool) bhpanShareExpiry(
  String raw, {
  DateTime? now,
  bool withTime = true,
}) {
  if (raw == bhpanNeverExpires) return ('长期有效', false);
  final time = DateTime.tryParse(raw);
  if (time == null) return ('有效期未知', false);
  final local = time.toUtc().add(const Duration(hours: 8));
  final date = '${local.year}年${local.month}月${local.day}日';
  final text = withTime
      ? '$date ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
      : date;
  return time.isBefore(now ?? DateTime.now())
      ? ('已于$text过期', true)
      : ('$text到期', false);
}

String bhpanShareRules(BhpanShare s) => [
  s.passwordRequired ? '需要提取码' : '无需提取码',
  s.limitedTimes == -1 ? '不限次数' : '限 ${s.limitedTimes} 次',
].join(' · ');

/// 分享管理：全部分享，或某个条目的分享记录。
class BhpanSharesPage extends StatefulWidget {
  const BhpanSharesPage({
    super.key,
    required this.service,
    required this.runWrite,
    required this.scope,
    this.item,
  });
  final BhpanService service;
  final BhpanWriteRunner? runWrite;
  final ValueListenable<int> scope;
  final BhpanItem? item;
  @override
  State<BhpanSharesPage> createState() => _BhpanSharesPageState();
}

class _BhpanSharesPageState extends State<BhpanSharesPage> {
  List<BhpanShare>? _shares;
  Object? _error;
  bool _loading = false, _working = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation;
  Widget _boundary(Widget child) =>
      UiScopeBoundary(generation: widget.scope, child: child);

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shares = await widget.service.shares(item: widget.item?.handle);
      if (_current(generation)) setState(() => _shares = shares);
    } on Object catch (e) {
      if (_current(generation)) setState(() => _error = e);
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _mutate(BhpanMutation request) async {
    final run = widget.runWrite;
    if (run == null || _working) return;
    final generation = _generation;
    setState(() => _working = true);
    try {
      final result = await run(request);
      if (!_current(generation) || result == null) return;
      bhpanShowOutcome(context, request.kind, result);
      if (result.error == null ||
          result.error?.code == UbaaErrorCode.outcomeUnknown)
        await _load();
    } on Object catch (e) {
      if (_current(generation))
        UbaaFeedback.show(
          context,
          e is UiError ? e.message : '操作失败，请检查网络后重试',
          kind: UbaaFeedbackKind.error,
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _open(BhpanShare share) async {
    final action = await showUiSheet<String>(
      context,
      builder: (_) => _boundary(
        _ShareSheet(
          share: share,
          service: widget.service,
          writable: widget.runWrite != null && !_working,
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'cancel') {
      await _mutate(
        BhpanMutation(BhpanMutationKind.cancelShare, target: share.handle),
      );
      return;
    }
    final generation = _generation;
    final settings = await bhpanShareDialog(
      context,
      scope: widget.scope,
      title: share.title,
      existing: share,
    );
    if (!_current(generation) || settings == null) return;
    await _mutate(
      BhpanMutation(
        BhpanMutationKind.updateShare,
        target: share.handle,
        settings: settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shares = _shares;
    Widget content;
    if (_error case final error?) {
      content = PullToRefresh(
        onRefresh: _load,
        child: RefreshViewport(
          child: UiStatePanel(
            icon: Icons.cloud_off_outlined,
            title: '分享读取失败',
            detail: error is UiError ? error.message : '请检查网络后重试',
            action: '重试',
            onAction: _loading ? null : _load,
          ),
        ),
      );
    } else if (shares == null) {
      content = const LoadingPlaceholder();
    } else if (shares.isEmpty) {
      content = PullToRefresh(
        onRefresh: _load,
        child: RefreshViewport(
          child: UiStatePanel(
            icon: Icons.link_off,
            title: widget.item == null ? '还没有分享' : '这个条目还没有分享',
            detail: '在文件的「更多操作」里选择「分享」即可创建链接',
          ),
        ),
      );
    } else {
      content = PullToRefresh(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: shares.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final s = shares[index];
            final (expiry, expired) = bhpanShareExpiry(
              s.expiresAt,
              withTime: false,
            );
            return ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (expired ? colors.error : colors.primary).withValues(
                    alpha: .12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  expired ? Icons.link_off : Icons.link,
                  color: expired ? colors.error : colors.primary,
                ),
              ),
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                '${bhpanShareRules(s)} · $expiry',
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: expired ? colors.error : colors.onSurfaceVariant,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: colors.outline),
              enabled: !_working,
              onTap: () => _open(s),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item == null ? '分享管理' : '「${widget.item!.name}」的分享',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: content,
    );
  }
}

/// 分享详情：自动读取链接，提供复制、修改和取消。
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.share,
    required this.service,
    required this.writable,
  });
  final BhpanShare share;
  final BhpanService service;
  final bool writable;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final Future<String> _link = widget.service.shareLink(
    widget.share.handle,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = widget.share;
    final (expiry, expired) = bhpanShareExpiry(s.expiresAt);
    return UiSheetBody(
      title: s.title,
      subtitle: bhpanShareRules(s),
      children: [
        UiInfoRow(
          icon: Icons.event_outlined,
          text: expiry,
          color: expired ? colors.error : null,
        ),
        const SizedBox(height: 10),
        FutureBuilder<String>(
          future: _link,
          builder: (context, snap) =>
              _LinkBox(link: snap.data, failed: snap.hasError),
        ),
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: widget.writable && s.canUpdate
              ? () => Navigator.pop(context, 'edit')
              : null,
          icon: const Icon(Icons.tune),
          label: const Text('修改设置'),
        ),
        OutlinedButton.icon(
          onPressed: widget.writable
              ? () => Navigator.pop(context, 'cancel')
              : null,
          style: OutlinedButton.styleFrom(foregroundColor: colors.error),
          icon: const Icon(Icons.link_off),
          label: const Text('取消分享'),
        ),
      ],
    );
  }
}

/// 链接框：读取中显示加载，读到后可选中，右侧按钮复制。
class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.link, this.failed = false});
  final String? link;
  final bool failed;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final link = this.link;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: link != null
                ? SelectableText(link, style: theme.textTheme.bodyMedium)
                : failed
                ? Text('分享链接读取失败', style: TextStyle(color: colors.error))
                : const Align(
                    alignment: Alignment.centerLeft,
                    child: LoadingGlyph(dimension: 18),
                  ),
          ),
          IconButton(
            tooltip: '复制链接',
            onPressed: link == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted)
                      UbaaFeedback.show(
                        context,
                        '已复制分享链接',
                        kind: UbaaFeedbackKind.success,
                      );
                  },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

/// 分享链接弹窗：创建成功后与分享管理共用，复制后给出提示。
Future<void> bhpanShowShareLink(
  BuildContext context, {
  required BhpanService service,
  required BhpanShare share,
  required Widget Function(Widget) boundary,
  required bool Function() isCurrent,
}) async {
  try {
    final link = await service.shareLink(share.handle);
    if (!isCurrent() || !context.mounted) return;
    await showUiSheet<void>(
      context,
      builder: (c) => boundary(
        UiSheetBody(
          title: share.title,
          children: [SelectableText(link)],
          primaryAction: FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (c.mounted) Navigator.pop(c);
              if (context.mounted)
                UbaaFeedback.show(
                  context,
                  '已复制分享链接',
                  kind: UbaaFeedbackKind.success,
                );
            },
            child: const Text('复制分享链接'),
          ),
        ),
      ),
    );
  } on Object catch (e) {
    if (isCurrent() && context.mounted)
      UbaaFeedback.show(
        context,
        e is UiError ? e.message : '分享链接读取失败，请重试',
        kind: UbaaFeedbackKind.error,
      );
  }
}
