part of '../../widgets.dart';

/// 旧版阳光首页：概要在前、记录在后，运动项目收在新增流程。
class _YgdkHomeFlow extends StatefulWidget {
  const _YgdkHomeFlow({
    required this.snapshot,
    required this.query,
    required this.cacheEpoch,
    required this.filter,
    required this.fallback,
    this.onQuery,
    this.onSubmit,
    this.onPickPhoto,
    this.recordsReadback,
  });
  final FeatureSnapshot snapshot;
  final FeatureSnapshot? recordsReadback;
  final FeatureQuery query;
  final int cacheEpoch;
  final String filter;
  final Widget fallback;
  final Future<void> Function(FeatureQuery)? onQuery;
  final YgdkSubmitStarter? onSubmit;
  final YgdkPhotoPicker? onPickPhoto;
  @override
  State<_YgdkHomeFlow> createState() => _YgdkHomeFlowState();
}

class _YgdkHomeFlowState extends State<_YgdkHomeFlow> {
  FeatureSnapshot? _consumed;
  FeatureSnapshot? _consumedReadback;
  YgdkOverview? _overview;
  List<FeatureDetail> _items = [];
  List<YgdkRecordPresentation> _records = [];
  ConnectionMode? _route;
  YgdkHomeRecords? _page;
  int? _appendPage, _afterRevision;
  bool _initialRequested = false, _requesting = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consume();
  }

  @override
  void didUpdateWidget(covariant _YgdkHomeFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _generation++;
      _overview = null;
      _items = [];
      _records = [];
      _page = null;
      _consumed = null;
      _consumedReadback = null;
      _initialRequested = false;
      _afterRevision = oldWidget.snapshot.readContext?.requestRevision ?? -1;
    }
    _consume();
  }

  void _consume() {
    if (!TickerMode.valuesOf(context).enabled) return;
    final snapshot = widget.snapshot;
    if (snapshot.status != FeatureLoadStatus.success &&
        snapshot.status != FeatureLoadStatus.stale)
      return;
    if (_afterRevision != null &&
        (snapshot.readContext?.requestRevision ?? -1) <= _afterRevision!)
      return;
    final overview = snapshot.overview;
    if (overview is! YgdkOverview) return;
    if (!identical(snapshot, _consumed) ||
        !identical(widget.recordsReadback, _consumedReadback)) {
      _afterRevision = null;
      _consumed = snapshot;
      _consumedReadback = widget.recordsReadback;
      var next = overview.records;
      final readback = widget.recordsReadback;
      if (next == null &&
          readback != null &&
          readback.readContext?.requestRevision ==
              snapshot.readContext?.requestRevision &&
          readback.readContext?.query?.view == FeatureQueryView.ygdkRecords) {
        if (readback.status == FeatureLoadStatus.failure) {
          next = YgdkHomeRecords(
            page: 1,
            size: 20,
            errorCode: readback.error?.code ?? UbaaErrorCode.internalError,
          );
        } else if ((readback.status == FeatureLoadStatus.success ||
                readback.status == FeatureLoadStatus.empty) &&
            readback.resolvedRoute == snapshot.resolvedRoute) {
          next = YgdkHomeRecords(
            page: readback.pagination?.page ?? 1,
            size: readback.pagination?.size ?? 20,
            total: readback.pagination?.total,
            hasMore: readback.pagination?.hasMore,
            content: readback.details
                .map((d) => d.presentation)
                .whereType<YgdkRecordPresentation>()
                .toList(),
          );
        }
      }
      if (next != null && next.errorCode == null) {
        final append =
            _appendPage == next.page &&
            _page?.page == next.page - 1 &&
            _page?.size == next.size &&
            _route == snapshot.resolvedRoute;
        _records = append ? [..._records, ...next.content] : [...next.content];
      } else if (_route != snapshot.resolvedRoute || next == null) {
        _records = [];
      }
      _page = next;
      _appendPage = null;
      _overview = overview;
      _items = snapshot.details;
      _route = snapshot.resolvedRoute;
    }
    // 仅页面首次消费后台默认读取时补记录。显式查询及写后固定回读不触发Auto。
    if (!_initialRequested &&
        overview.records == null &&
        snapshot.readContext != null &&
        snapshot.readContext?.query == null &&
        widget.onQuery != null) {
      _initialRequested = true;
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _generation &&
            TickerMode.valuesOf(context).enabled) {
          unawaited(_load(const FeatureQuery()));
        } else if (mounted) {
          _initialRequested = false;
        }
      });
    }
  }

  Future<void> _load(FeatureQuery query, {bool append = false}) async {
    if (_requesting || widget.onQuery == null) return;
    setState(() {
      _requesting = true;
      _appendPage = append ? query.page : null;
    });
    try {
      await widget.onQuery!(query);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _add() async {
    final selected = await showDialog<FeatureDetail>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择运动项目'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final detail in _items.where(
                  (d) => d.presentation is YgdkItemPresentation,
                ))
                  ListTile(
                    title: Text(
                      (detail.presentation as YgdkItemPresentation).name,
                    ),
                    subtitle:
                        detail.action<YgdkSubmitAction>()?.hasCanonicalTarget ==
                            true
                        ? null
                        : const Text('当前不可提交'),
                    enabled:
                        detail.action<YgdkSubmitAction>()?.hasCanonicalTarget ==
                        true,
                    onTap: () => Navigator.pop(context, detail),
                  ),
                if (_items.isEmpty) const Text('暂无可用运动项目'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || !_items.contains(selected)) return;
    final action = selected.action<YgdkSubmitAction>();
    if (action?.hasCanonicalTarget != true) return;
    final input = await showDialog<YgdkSubmitInput>(
      context: context,
      builder: (_) => _YgdkFormDialog(
        action: action!,
        title: (selected.presentation as YgdkItemPresentation).name,
        onPickPhoto: widget.onPickPhoto,
      ),
    );
    if (mounted && input != null && _items.contains(selected))
      await widget.onSubmit?.call(input);
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    if (overview == null) return widget.fallback;
    final loading =
        _requesting || widget.snapshot.status == FeatureLoadStatus.loading;
    final filter = widget.filter.trim().toLowerCase();
    final visible = _records
        .where(
          (p) => _ygdkRecordSearchValues(
            p,
          ).any((v) => v.toLowerCase().contains(filter)),
        )
        .toList();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _YgdkSummary(overview),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '打卡记录',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (loading) const LinearProgressIndicator(),
            if (_page?.errorCode != null ||
                widget.snapshot.status == FeatureLoadStatus.stale) ...[
              const Text('打卡记录加载失败，请重试。'),
              TextButton(
                onPressed: loading ? null : () => _load(widget.query),
                child: const Text('重试记录'),
              ),
              if (_records.isNotEmpty) const Text('以下为上次成功加载的记录。'),
            ] else if (_page == null && !loading)
              TextButton(
                onPressed: () => _load(widget.query),
                child: const Text('加载打卡记录'),
              ),
            if (_page != null &&
                _page!.errorCode == null &&
                !loading &&
                visible.isEmpty)
              Text(filter.isEmpty ? '暂时还没有打卡记录' : '没有匹配的打卡记录'),
            for (final record in visible) ...[
              _YgdkRecordCard(record),
              const SizedBox(height: 12),
            ],
            if (_page?.hasMore == true && _page?.errorCode == null)
              OutlinedButton(
                onPressed: loading
                    ? null
                    : () => _load(
                        FeatureQuery(page: _page!.page + 1, size: _page!.size),
                        append: true,
                      ),
                child: Text(loading ? '加载中…' : '加载更多'),
              ),
          ],
        ),
        if (widget.onSubmit != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              tooltip: '新增打卡',
              onPressed:
                  loading || widget.snapshot.status != FeatureLoadStatus.success
                  ? null
                  : _add,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}
