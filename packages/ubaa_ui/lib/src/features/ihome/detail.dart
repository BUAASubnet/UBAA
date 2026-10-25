part of 'view.dart';

class _IhomeDetail extends StatefulWidget {
  const _IhomeDetail({
    required this.service,
    required this.id,
    required this.mine,
    required this.config,
  });
  final IhomeService service;
  final int id;
  final bool mine;
  final IhomeConfig? config;
  @override
  State<_IhomeDetail> createState() => _IhomeDetailState();
}

class _IhomeDetailState extends State<_IhomeDetail> {
  IhomeResult<IhomeAppeal>? _value;
  bool _loading = true, _writing = false, _needsRefresh = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.detail(widget.id, mine: widget.mine);
      if (mounted)
        setState(() {
          _value = result;
          _needsRefresh = false;
        });
    } on Object catch (e) {
      if (mounted)
        setState(() => _error = e is UiError ? e.message : '详情读取失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _react(IhomeReaction reaction, bool enabled) async {
    if (_writing || _loading || _needsRefresh || _value == null) return;
    final route = _value!.route;
    final action = reaction == IhomeReaction.follow
        ? '关注'
        : widget.config?.supportLabel ?? '支持';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${enabled ? '' : '取消'}$action'),
        content: Text('确认${enabled ? '' : '取消'}$action这条诉求？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      final result = await widget.service.setReaction(
        widget.id,
        reaction,
        enabled,
        route,
      );
      if (mounted) setState(() => _value = result);
    } on Object catch (e) {
      if (mounted)
        setState(() {
          _error = e is UiError ? e.message : '操作结果未确认，请刷新详情后核对';
          _needsRefresh = true;
        });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appeal = _value?.data;
    return PopScope(
      canPop: !_writing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('诉求详情'),
          automaticallyImplyLeading: !_writing,
          actions: [
            IconButton(
              tooltip: '刷新详情',
              onPressed: _loading || _writing ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _IhomeBody(
          children: [
            if (_loading || _writing) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _writing ? null : _load,
                      child: const Text('刷新核对'),
                    ),
                  ],
                ),
              ),
            if (appeal != null) ...[
              SelectableText(
                appeal.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Text(
                [
                  appeal.category,
                  appeal.status,
                  appeal.publishedAt,
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
              if (appeal.departments.isNotEmpty)
                Text(appeal.departments.join('、')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _loading ||
                            _writing ||
                            _needsRefresh ||
                            appeal.isFollowed == null
                        ? null
                        : () =>
                              _react(IhomeReaction.follow, !appeal.isFollowed!),
                    icon: Icon(
                      appeal.isFollowed == true
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    label: Text(
                      '${appeal.isFollowed == true ? '已关注' : '关注'}${appeal.followCount == null ? '' : ' ${appeal.followCount}'}',
                    ),
                  ),
                  if (widget.config?.supportEnabled == true)
                    OutlinedButton.icon(
                      onPressed:
                          _loading ||
                              _writing ||
                              _needsRefresh ||
                              appeal.isSupported == null
                          ? null
                          : () => _react(
                              IhomeReaction.support,
                              !appeal.isSupported!,
                            ),
                      icon: Icon(
                        appeal.isSupported == true
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                      ),
                      label: Text(
                        '${appeal.isSupported == true ? '已' : ''}${widget.config!.supportLabel}${appeal.supportCount == null ? '' : ' ${appeal.supportCount}'}',
                      ),
                    ),
                ],
              ),
              if (appeal.replies.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('官方回复', style: Theme.of(context).textTheme.titleMedium),
                for (final reply in appeal.replies)
                  _block(
                    context,
                    reply.department,
                    reply.content,
                    reply.createdAt,
                  ),
              ],
              if (appeal.evaluations.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('评价', style: Theme.of(context).textTheme.titleMedium),
                for (final e in appeal.evaluations)
                  _block(
                    context,
                    e.department,
                    '响应速度 ${e.speed} · 满意度 ${e.satisfaction} · 解决程度 ${e.degree}\n${e.content}',
                    e.createdAt,
                  ),
              ],
              if (appeal.history.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('处理进度', style: Theme.of(context).textTheme.titleMedium),
                for (final h in appeal.history)
                  _block(context, '', h.content, h.createdAt),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, String title, String body, String date) =>
      Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              SelectableText(body),
              if (date.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    date,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _IhomeNoticeView extends StatefulWidget {
  const _IhomeNoticeView({required this.service, required this.id});
  final IhomeService service;
  final int id;
  @override
  State<_IhomeNoticeView> createState() => _IhomeNoticeViewState();
}

class _IhomeNoticeViewState extends State<_IhomeNoticeView> {
  late Future<IhomeResult<IhomeNotice>> _future = widget.service.notice(
    widget.id,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('公告详情')),
    body: FutureBuilder<IhomeResult<IhomeNotice>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _future = widget.service.notice(widget.id)),
              child: const Text('读取失败，点击重试'),
            ),
          );
        final notice = snapshot.data!.data;
        return _IhomeBody(
          children: [
            Text(notice.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(notice.date),
            const SizedBox(height: 20),
            SelectableText(notice.content),
          ],
        );
      },
    ),
  );
}

class _IhomeBody extends StatelessWidget {
  const _IhomeBody({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: UbaaTheme.pageMaxWidth),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );
}
