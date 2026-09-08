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
  final ValueChanged<FeatureSnapshot> onVisibleSnapshot;
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
      _current.query == null || widget.onQuery == null
      ? widget.onRetry()
      : _query(_current, _current.query!);

  Future<void> _query(_ReadFrame frame, FeatureQuery query) async {
    if (widget.onQuery == null || !identical(frame, _current)) return;
    setState(() {
      _externalAfterRevision = null;
      frame.query = query;
    });
    await widget.onQuery!(query);
  }

  Future<void> _navigate(FeatureReadNavigation target) async {
    if (widget.onQuery == null ||
        target.feature != widget.snapshot.feature ||
        _current.snapshot.status == FeatureLoadStatus.loading)
      return;
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

  @override
  Widget build(BuildContext context) {
    final visible = _current.snapshot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(visible, _current.snapshot))
        widget.onVisibleSnapshot(visible);
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
                  snapshot: frame.snapshot,
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
  _ReadFrame(this.id, this.snapshot, this.query);
  final pageKey = GlobalKey<_FeatureDetailViewState>();
  final int id;
  FeatureSnapshot snapshot;
  FeatureQuery? query;
}

class _ReadPage {
  const _ReadPage({
    required this.pageKey,
    required this.snapshot,
    required this.query,
    required this.backLabel,
    required this.onBack,
    required this.onRetry,
    this.onQuery,
    this.onNavigate,
  });
  final GlobalKey<_FeatureDetailViewState> pageKey;
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final String backLabel;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;
}
