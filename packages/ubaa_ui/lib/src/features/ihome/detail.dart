part of 'view.dart';

extension _IhomeCards on _IhomeViewState {
  Widget _appealCard(BuildContext context, IhomeEntry entry) {
    final id = entry.appeal.id;
    final appeal = _details[id]?.data ?? entry.appeal;
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
          InkWell(
            onTap: busy ? null : () => _toggle(entry),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appeal.content,
                    maxLines: expanded ? null : 4,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      appeal.category,
                      appeal.status,
                      appeal.publishedAt,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (!expanded && appeal.replies.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      '${appeal.replies.first.department}：${appeal.replies.first.content}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled || appeal.isFollowed == null
                      ? null
                      : () => _react(appeal, IhomeReaction.follow),
                  icon: Icon(
                    appeal.isFollowed == true
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                  label: Text(
                    '${appeal.isFollowed == true ? '已关注' : '关注'}${appeal.followCount == null ? '' : ' ${appeal.followCount}'}',
                  ),
                ),
                if (_config?.supportEnabled == true)
                  OutlinedButton.icon(
                    onPressed: disabled || appeal.isSupported == null
                        ? null
                        : () => _react(appeal, IhomeReaction.support),
                    icon: Icon(
                      appeal.isSupported == true
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined,
                    ),
                    label: Text(
                      '${appeal.isSupported == true ? '已' : ''}${_config!.supportLabel}${appeal.supportCount == null ? '' : ' ${appeal.supportCount}'}',
                    ),
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
          if (expanded && _details.containsKey(id))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (appeal.departments.isNotEmpty)
                    Text(appeal.departments.join('、')),
                  if (appeal.replies.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '官方回复',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final r in appeal.replies)
                      _ihomeBlock(
                        context,
                        r.department,
                        r.content,
                        r.createdAt,
                      ),
                  ],
                  if (appeal.evaluations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('评价', style: Theme.of(context).textTheme.titleMedium),
                    for (final e in appeal.evaluations)
                      _ihomeBlock(
                        context,
                        e.department,
                        '响应速度 ${e.speed} · 满意度 ${e.satisfaction} · 解决程度 ${e.degree}\n${e.content}',
                        e.createdAt,
                      ),
                  ],
                  if (appeal.history.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '处理进度',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final h in appeal.history)
                      _ihomeBlock(context, '', h.content, h.createdAt),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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
