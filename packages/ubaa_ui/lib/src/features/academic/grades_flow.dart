part of '../../widgets.dart';

/// 旧版两张统计卡和课程列表共用滚动区域，面板筛选不改变统计集合。
class _GradesFlow extends StatefulWidget {
  const _GradesFlow({
    required this.snapshot,
    required this.visible,
    required this.cacheEpoch,
    required this.filter,
    required this.fallback,
    this.loader,
    this.onRoutes,
  });
  final FeatureSnapshot snapshot;
  final bool visible;
  final int cacheEpoch;
  final String filter;
  final Widget fallback;
  final Future<GradesAggregate> Function(bool)? loader;
  final ValueChanged<Map<String, ConnectionMode>>? onRoutes;
  @override
  State<_GradesFlow> createState() => _GradesFlowState();
}

class _GradesFlowState extends State<_GradesFlow> {
  GradesAggregate? _aggregate;
  bool _loading = false, _refreshAfterRead = false, _scheduled = false;
  int _serial = 0;
  bool get _ready => {
    FeatureLoadStatus.success,
    FeatureLoadStatus.empty,
    FeatureLoadStatus.stale,
  }.contains(widget.snapshot.status);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _GradesFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _serial++;
      _aggregate = null;
      _loading = false;
      _refreshAfterRead = false;
    } else if (widget.snapshot.status == FeatureLoadStatus.loading &&
        oldWidget.snapshot.status != FeatureLoadStatus.loading &&
        oldWidget.snapshot.readContext?.hasSameQuery(
              widget.snapshot.readContext?.query,
            ) ==
            true) {
      _refreshAfterRead = true;
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled ||
        !widget.visible ||
        !_ready ||
        _loading ||
        widget.loader == null ||
        (_aggregate != null && !_refreshAfterRead))
      return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && widget.visible && _ready && !_loading) {
        unawaited(_load(force: _refreshAfterRead));
      }
    });
  }

  Future<void> _load({required bool force}) async {
    final loader = widget.loader;
    if (loader == null) return;
    final serial = ++_serial;
    setState(() {
      _loading = true;
      _refreshAfterRead = false;
    });
    GradesAggregate result;
    try {
      result = await loader(force);
    } on Object {
      result = const GradesAggregate(
        error: UiError(
          code: UbaaErrorCode.internalError,
          title: '统计暂不可用',
          message: '暂时无法读取全部学期，请稍后重试。',
        ),
      );
    }
    if (!mounted || serial != _serial) return;
    setState(() {
      _aggregate = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final value = snapshot.overview;
    final current = value is GradesTermOverview ? value : null;
    final aggregate = _aggregate;
    final routes = <String, ConnectionMode>{
      if (_ready && snapshot.resolvedRoute != null)
        '本学期': snapshot.resolvedRoute!,
      if (_ready && aggregate?.error == null)
        for (final term in aggregate?.terms ?? const <GradeTermRead>[])
          if (term.overview != null && term.resolvedRoute != null)
            '全部成绩 · ${term.name}': term.resolvedRoute!,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.visible) widget.onRoutes?.call(routes);
    });
    if (!_ready ||
        current == null ||
        !_supportsAcademicContent(FeatureId.grades, snapshot.details))
      return widget.fallback;
    final filter = widget.filter.trim().toLowerCase();
    final details = snapshot.details
        .where(
          (detail) =>
              filter.isEmpty ||
              <String>[
                detail.title,
                if (detail.subtitle != null) detail.subtitle!,
                ..._academicSearchValues(detail.presentation),
                for (final field in detail.fields) ...[
                  field.label,
                  field.value,
                ],
              ].any((value) => value.toLowerCase().contains(filter)),
        )
        .toList();
    return ListView(
      key: const PageStorageKey('grades-old-list'),
      padding: const EdgeInsets.all(16),
      children: [
        if (snapshot.status == FeatureLoadStatus.stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('${snapshot.error?.message ?? '刷新失败。'} 以下为上次成功加载的数据。'),
          ),
        _GradeSummaryCard(
          title: '全部成绩',
          statistics: aggregate?.statistics,
          loading: _loading || (widget.loader != null && aggregate == null),
          notice: aggregate?.error != null
              ? aggregate!.error!.message
              : aggregate != null && !aggregate.isComplete
              ? '部分统计 · 已读取 ${aggregate.loadedTerms}/${aggregate.terms.length} 个学期'
              : widget.loader == null
              ? '全部学期统计暂不可用'
              : null,
          onRetry:
              widget.loader != null &&
                  !_loading &&
                  aggregate != null &&
                  !aggregate.isComplete
              ? () => _load(force: false)
              : null,
        ),
        const SizedBox(height: 12),
        _GradeSummaryCard(
          title: '本学期',
          statistics: GradeStatistics.calculate(current.grades),
          showCourseAndCredits: true,
        ),
        const SizedBox(height: 12),
        if (details.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(filter.isNotEmpty ? '没有匹配的成绩' : '暂无成绩')),
          )
        else
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GradeCard(detail: detail),
            ),
      ],
    );
  }
}
