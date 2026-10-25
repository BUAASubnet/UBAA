part of 'view.dart';

extension _IhomeCards on _IhomeViewState {
  Widget _appealCard(BuildContext context, IhomeEntry entry) {
    final id = entry.appeal.id;
    // 详情读取只补充进度与操作状态，列表正文保持原位，避免打断选择复制。
    final appeal = entry.appeal;
    final detail = _details[id]?.data;
    final reaction = detail ?? appeal;
    final expanded = _expanded.contains(_entryKey(entry));
    final busy = _busy.contains(id), loading = _detailLoading.contains(id);
    final disabled = _loading || busy || loading || _uncertain.contains(id);
    return Card(
      key: ValueKey(_entryKey(entry)),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(appeal.content),
                const SizedBox(height: 8),
                Text(
                  [
                    appeal.category,
                    appeal.status,
                    appeal.publishedAt,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (appeal.replies.isNotEmpty) ...[
                  const Divider(),
                  for (final reply in appeal.replies)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: SelectableText(
                        reply.department.isEmpty
                            ? reply.content
                            : '${reply.department}：${reply.content}',
                      ),
                    ),
                ],
                if (entry.evaluation != null) ...[
                  const Divider(),
                  Text('我的评价：${entry.evaluation!.content}'),
                  Text(
                    '响应速度 ${entry.evaluation!.speed} · 满意度 ${entry.evaluation!.satisfaction} · 解决程度 ${entry.evaluation!.degree}',
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ihomeReaction(
                  context,
                  selected: reaction.isFollowed == true,
                  label: '关注',
                  icon: Icons.star_border,
                  selectedIcon: Icons.star,
                  count: reaction.followCount,
                  onPressed: disabled || reaction.isFollowed == null
                      ? null
                      : () => _react(reaction, IhomeReaction.follow),
                ),
                if (_config?.supportEnabled == true)
                  _ihomeReaction(
                    context,
                    selected: reaction.isSupported == true,
                    label: _config!.supportLabel,
                    icon: Icons.thumb_up_outlined,
                    selectedIcon: Icons.thumb_up,
                    count: reaction.supportCount,
                    onPressed: disabled || reaction.isSupported == null
                        ? null
                        : () => _react(reaction, IhomeReaction.support),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : () => _toggle(entry),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(expanded ? '收起详情' : '查看详情'),
                ),
              ],
            ),
          ),
          if (loading || _submitting.contains(id))
            const LinearProgressIndicator(),
          if (_detailErrors[id] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_detailErrors[id]!),
                  TextButton(
                    onPressed: loading || busy ? null : () => _readDetail(id),
                    child: Text(_uncertain.contains(id) ? '刷新核对' : '重试'),
                  ),
                ],
              ),
            ),
          if (expanded && detail != null && detail.history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text('处理进度', style: Theme.of(context).textTheme.titleMedium),
                  for (final history in detail.history)
                    _ihomeBlock(
                      context,
                      '',
                      history.content,
                      history.createdAt,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 沿旧版使用图标切换和独立数量，视觉紧凑并保留完整点击区域。
Widget _ihomeReaction(
  BuildContext context, {
  required bool selected,
  required String label,
  required IconData icon,
  required IconData selectedIcon,
  required int? count,
  required VoidCallback? onPressed,
}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      tooltip: selected ? '取消$label' : label,
      isSelected: selected,
      iconSize: 20,
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon),
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
    ),
    if (count != null)
      Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
  ],
);

Widget _ihomeBlock(
  BuildContext context,
  String title,
  String body,
  String date,
) => Padding(
  padding: const EdgeInsets.only(top: 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title.isNotEmpty)
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      SelectableText(body),
      if (date.isNotEmpty)
        Text(date, style: Theme.of(context).textTheme.bodySmall),
    ],
  ),
);

class _IhomeNoticeCard extends StatefulWidget {
  const _IhomeNoticeCard({
    required this.service,
    required this.notice,
    super.key,
  });
  final IhomeService service;
  final IhomeNotice notice;
  @override
  State<_IhomeNoticeCard> createState() => _IhomeNoticeCardState();
}

class _IhomeNoticeCardState extends State<_IhomeNoticeCard> {
  Future<IhomeResult<IhomeNotice>>? _future;
  bool _expanded = false;
  @override
  void didUpdateWidget(covariant _IhomeNoticeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notice, widget.notice) ||
        !identical(oldWidget.service, widget.service)) {
      _future = _expanded ? widget.service.notice(widget.notice.id) : null;
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(widget.notice.title),
          subtitle: Text(widget.notice.date),
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() {
            _expanded = !_expanded;
            if (_expanded) _future ??= widget.service.notice(widget.notice.id);
          }),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FutureBuilder<IhomeResult<IhomeNotice>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const LinearProgressIndicator();
                if (snapshot.hasError)
                  return TextButton(
                    onPressed: () => setState(
                      () => _future = widget.service.notice(widget.notice.id),
                    ),
                    child: const Text('读取失败，点击重试'),
                  );
                return SelectableText(snapshot.data!.data.content);
              },
            ),
          ),
      ],
    ),
  );
}
