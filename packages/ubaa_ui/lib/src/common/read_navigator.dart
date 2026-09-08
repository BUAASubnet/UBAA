part of '../widgets.dart';

/// 父页只保存展示快照，不回写 AppController 或作为写入核对依据。
class _FeatureReadNavigator extends StatefulWidget {
  const _FeatureReadNavigator({
    required this.snapshot,
    required this.cacheEpoch,
    required this.onExit,
    required this.onRetry,
    required this.pageBuilder,
    required this.onVisibleSnapshot,
    this.onQuery,
    super.key,
  });
  final void Function(FeatureSnapshot, String) onVisibleSnapshot;
  final FeatureSnapshot snapshot;
  final int cacheEpoch;
  final VoidCallback onExit;
  final Future<void> Function() onRetry;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Widget Function(_ReadPage) pageBuilder;
  @override
  State<_FeatureReadNavigator> createState() => _FeatureReadNavigatorState();
}

class _FeatureReadNavigatorState extends State<_FeatureReadNavigator> {
  final List<_ReadFrame> _frames = [];
  int _nextId = 0;
  int? _externalAfterRevision;
  _ReadFrame get _current => _frames.last;
  @override
  void initState() {
    super.initState();
    _frames.add(
      _ReadFrame(
        _nextId++,
        widget.snapshot,
        widget.snapshot.readContext?.query,
        isLanding:
            widget.onQuery != null && _hasLandingMenu(widget.snapshot.feature),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _FeatureReadNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.snapshot;
    final context = incoming.readContext;
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      final current = _current;
      _frames
        ..clear()
        ..add(current);
      // 失效通知可能仍携带旧子页快照；只接收边界之后的新读取代次。
      _externalAfterRevision =
          oldWidget.snapshot.readContext?.requestRevision ?? -1;
    }
    if (_current.isLanding) {
      _current.snapshot = incoming;
      return;
    }
    if (context != null &&
        _externalAfterRevision != null &&
        context.requestRevision > _externalAfterRevision!) {
      _externalAfterRevision = null;
      if (!context.hasSameQuery(_current.query)) {
        _frames[0] = _ReadFrame(_nextId++, incoming, context.query);
        return;
      }
    }
    if (!identical(incoming, oldWidget.snapshot) &&
        (context == null || context.hasSameQuery(_current.query))) {
      _current.snapshot = incoming;
      if (_current.bykcChosenKey != null && context != null) {
        // 本地详情与父列表共享同一次已选查询；新结果也更新父页，防止返回复活旧记录。
        for (final frame in _frames) {
          if (!identical(frame, _current) &&
              context.hasSameQuery(frame.query)) {
            frame.snapshot = incoming;
          }
        }
      }
    }
  }

  void openPanel() => _current.pageKey.currentState?.togglePanel();

  void goBack() {
    if (_frames.length == 1) {
      widget.onExit();
    } else {
      setState(() => _frames.removeLast());
    }
  }

  Future<void> refreshCurrent() =>
      _current.isLanding || _current.query == null || widget.onQuery == null
      ? widget.onRetry()
      : _query(_current, _current.query!);

  Future<void> _query(_ReadFrame frame, FeatureQuery query) async {
    if (widget.onQuery == null || !identical(frame, _current)) return;
    if (frame.isLanding) {
      await _navigate(
        FeatureReadNavigation(feature: widget.snapshot.feature, query: query),
        force: true,
      );
      return;
    }
    setState(() {
      _externalAfterRevision = null;
      if (frame.query == null || !query.hasSameParameters(frame.query!))
        frame.bykcChosenKey = null;
      frame.query = query;
    });
    await widget.onQuery!(query);
  }

  Future<void> _navigate(
    FeatureReadNavigation target, {
    bool force = false,
  }) async {
    if (widget.onQuery == null ||
        target.feature != widget.snapshot.feature ||
        (_current.snapshot.status == FeatureLoadStatus.loading &&
            !_current.isLanding))
      return;
    final cached = _current.snapshot;
    final reuseDefault =
        !force &&
        _current.isLanding &&
        target.query.hasSameParameters(const FeatureQuery()) &&
        (cached.readContext?.query == null ||
            cached.readContext!.query!.hasSameParameters(target.query)) &&
        cached.status != FeatureLoadStatus.idle;
    if (reuseDefault) {
      setState(() {
        _externalAfterRevision = null;
        _frames.add(
          _ReadFrame(
            _nextId++,
            cached,
            cached.readContext?.query,
            navigationQuery: target.query,
          ),
        );
      });
      return;
    }
    final frame = _ReadFrame(
      _nextId++,
      FeatureSnapshot(
        feature: target.feature,
        status: FeatureLoadStatus.loading,
      ),
      target.query,
    );
    setState(() {
      _externalAfterRevision = null;
      _frames.add(frame);
    });
    await widget.onQuery!(target.query);
  }

  void _openBykcChosen(FeatureDetail detail) {
    if (widget.snapshot.feature != FeatureId.bykc ||
        _current.snapshot.status == FeatureLoadStatus.loading ||
        !_current.snapshot.details.any((d) => identical(d, detail)))
      return;
    final value = detail.presentation;
    if (value is! BykcChosenPresentation) return;
    setState(
      () => _frames.add(
        _ReadFrame(
          _nextId++,
          _current.snapshot,
          _current.query,
          bykcChosenKey: (value.recordId, value.courseId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _current.visibleSnapshot;
    final title = _current.bykcChosenKey != null
        ? '课程详情'
        : _readPageTitle(
            visible.feature,
            _current.query ?? _current.navigationQuery,
            _current.isLanding,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(visible, _current.visibleSnapshot))
        widget.onVisibleSnapshot(visible, title);
    });
    return IndexedStack(
      index: _frames.length - 1,
      children: [
        for (final frame in _frames)
          ExcludeFocus(
            key: ValueKey<int>(frame.id),
            excluding: !identical(frame, _current),
            child: TickerMode(
              enabled: identical(frame, _current),
              child: widget.pageBuilder(
                _ReadPage(
                  pageKey: frame.pageKey,
                  isLanding: frame.isLanding,
                  snapshot: frame.bykcChosenKey == null
                      ? frame.snapshot
                      : frame.visibleSnapshot,
                  isBykcChosenDetail: frame.bykcChosenKey != null,
                  onOpenBykcChosen: _openBykcChosen,
                  query: frame.query,
                  backLabel: _frames.indexOf(frame) == 0 ? '返回功能列表' : '返回上一层',
                  onBack: goBack,
                  onRetry: () => frame.query == null || widget.onQuery == null
                      ? widget.onRetry()
                      : _query(frame, frame.query!),
                  onQuery: widget.onQuery == null
                      ? null
                      : (query) => _query(frame, query),
                  onNavigate: widget.onQuery == null ? null : _navigate,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadFrame {
  _ReadFrame(
    this.id,
    this.snapshot,
    this.query, {
    this.isLanding = false,
    this.navigationQuery,
    this.bykcChosenKey,
  }) : menuSnapshot = FeatureSnapshot(feature: snapshot.feature);
  final bool isLanding;
  final FeatureQuery? navigationQuery;
  final FeatureSnapshot menuSnapshot;
  (int, int)? bykcChosenKey;
  FeatureSnapshot? _chosenSource, _chosenSnapshot;
  FeatureSnapshot get visibleSnapshot {
    if (isLanding) return menuSnapshot;
    final key = bykcChosenKey;
    if (key == null) return snapshot;
    if (!identical(_chosenSource, snapshot)) {
      final matches = snapshot.details
          .where(
            (d) =>
                d.presentation is BykcChosenPresentation &&
                (
                      (d.presentation! as BykcChosenPresentation).recordId,
                      (d.presentation! as BykcChosenPresentation).courseId,
                    ) ==
                    key,
          )
          .toList();
      final unique = matches.length == 1;
      _chosenSource = snapshot;
      _chosenSnapshot = snapshot.copyWith(
        details: unique ? matches : const [],
        clearPagination: true,
        status: !unique && snapshot.status == FeatureLoadStatus.success
            ? FeatureLoadStatus.empty
            : snapshot.status,
      );
    }
    return _chosenSnapshot!;
  }

  final pageKey = GlobalKey<_FeatureDetailViewState>();
  final int id;
  FeatureSnapshot snapshot;
  FeatureQuery? query;
}

class _ReadPage {
  const _ReadPage({
    required this.pageKey,
    required this.isLanding,
    required this.snapshot,
    required this.query,
    required this.backLabel,
    required this.onBack,
    required this.onRetry,
    this.onQuery,
    this.onNavigate,
    this.isBykcChosenDetail = false,
    this.onOpenBykcChosen,
  });
  final bool isBykcChosenDetail;
  final ValueChanged<FeatureDetail>? onOpenBykcChosen;
  final GlobalKey<_FeatureDetailViewState> pageKey;
  final bool isLanding;
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final String backLabel;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;
}
