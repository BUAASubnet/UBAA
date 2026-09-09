part of '../../widgets.dart';

enum _ScheduleAutoStage { terms, weeks }

bool _isWeeklyScheduleQuery(FeatureQuery? query) =>
    query?.view == FeatureQueryView.scheduleWeek ||
    (query?.view == FeatureQueryView.summary &&
        query?.term != null &&
        query?.week != null);

/// 使用现有可见查询状态推进旧版选择顺序；每一步实际路线仍由该快照提供。
class _ScheduleFlow extends StatefulWidget {
  const _ScheduleFlow({
    super.key,
    required this.snapshot,
    required this.query,
    required this.visible,
    required this.epoch,
    required this.loadWeeks,
    required this.adoptDraft,
    required this.child,
    this.onQuery,
    this.onTitle,
  });
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final bool visible;
  final int epoch;
  final Future<FeatureResult> Function(String, bool) loadWeeks;
  final Future<void> Function(FeatureQuery)? onQuery;
  final ValueChanged<FeatureQuery> adoptDraft;
  final ValueChanged<String?>? onTitle;
  final Widget child;
  @override
  State<_ScheduleFlow> createState() => _ScheduleFlowState();
}

class _ScheduleFlowState extends State<_ScheduleFlow> {
  _ScheduleAutoStage? _automatic;
  FeatureQuery? _expected;
  bool _started = false, _selectionNeeded = false;
  int _generation = 0;
  String? _weeksTerm, _metadataAttempt, _reportedTitle;
  FeatureResult? _weeks;
  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _ScheduleFlow old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch) {
      _generation++;
      _weeks = null;
      _weeksTerm = null;
      _metadataAttempt = null;
      _automatic = null;
      _expected = null;
      _started = false;
      _selectionNeeded = false;
    }
    if (!widget.visible && old.visible) {
      _generation++;
      _metadataAttempt = null;
    }
    if (old.snapshot.readContext?.requestRevision !=
        widget.snapshot.readContext?.requestRevision)
      _metadataAttempt = null;
    if (!_sameQuery(old.query, widget.query)) {
      _generation++;
      if (!_sameQuery(_expected, widget.query)) stopAutomatic(notify: false);
    }
    _scheduleSync();
  }

  bool _sameQuery(FeatureQuery? a, FeatureQuery? b) =>
      a == null ? b == null : b != null && a.hasSameParameters(b);

  void stopAutomatic({bool notify = true, bool clearPrompt = true}) {
    _generation++;
    _automatic = null;
    _expected = null;
    _started = true;
    if (clearPrompt) _selectionNeeded = false;
    if (notify && mounted) setState(() {});
  }

  void _scheduleSync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _sync();
  });

  bool get _settled =>
      {
        FeatureLoadStatus.success,
        FeatureLoadStatus.empty,
      }.contains(widget.snapshot.status) &&
      _sameQuery(widget.snapshot.readContext?.query, widget.query);

  void _sync() {
    if (!widget.visible || widget.onQuery == null) return;
    if (!_started && widget.query == null) {
      _started = true;
      _automatic = _ScheduleAutoStage.terms;
      _request(const FeatureQuery(view: FeatureQueryView.scheduleTerms));
      return;
    }
    if (_settled && widget.query?.view == FeatureQueryView.scheduleWeeks) {
      _weeksTerm = widget.query!.term;
      _weeks = FeatureResult.success(
        details: widget.snapshot.details,
        resolvedRoute: widget.snapshot.resolvedRoute,
      );
    }
    if (_automatic != null && _sameQuery(_expected, widget.query) && _settled) {
      if (_automatic == _ScheduleAutoStage.terms) {
        final selected = widget.snapshot.details
            .where(
              (d) =>
                  d.presentation is TermPresentation &&
                  (d.presentation! as TermPresentation).selected &&
                  (d.presentation! as TermPresentation).code.trim().isNotEmpty,
            )
            .toList();
        final term = selected.length == 1
            ? (selected.single.presentation! as TermPresentation).code
            : null;
        final unique =
            term != null &&
            widget.snapshot.details
                    .where(
                      (d) =>
                          d.presentation is TermPresentation &&
                          (d.presentation! as TermPresentation).code == term,
                    )
                    .length ==
                1;
        if (!unique) {
          _needSelection(null);
          return;
        }
        _automatic = _ScheduleAutoStage.weeks;
        _request(
          FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
        );
        return;
      }
      final term = widget.query!.term!;
      final current = _weekCandidates(
        term,
      ).where((d) => (d.presentation! as WeekPresentation).current).toList();
      final choice = current.length == 1 ? current.single : null;
      final number = choice == null
          ? null
          : (choice.presentation! as WeekPresentation).number;
      if (number == null ||
          _weekCandidates(term)
                  .where(
                    (d) =>
                        (d.presentation! as WeekPresentation).number == number,
                  )
                  .length !=
              1) {
        _needSelection(term);
        return;
      }
      _automatic = null;
      _request(
        FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: term,
          week: number,
        ),
      );
      return;
    }
    final query = widget.query;
    if (_settled &&
        _isWeeklyScheduleQuery(query) &&
        query?.term != null &&
        _weeksTerm != query!.term &&
        _metadataAttempt != query.term) {
      _metadataAttempt = query.term;
      final generation = _generation;
      final term = query.term!;
      unawaited(_loadMetadata(term, generation));
    }
    final title = _visibleWeek?.title;
    if (_reportedTitle != title) {
      _reportedTitle = title;
      widget.onTitle?.call(title);
    }
  }

  List<FeatureDetail> _weekCandidates(String term) => _weeksTerm != term
      ? const []
      : _weeks!.details
            .where(
              (d) =>
                  d.presentation is WeekPresentation &&
                  (d.presentation! as WeekPresentation).requestTerm == term &&
                  (d.presentation! as WeekPresentation).number > 0,
            )
            .toList();

  FeatureDetail? get _visibleWeek {
    final q = widget.query;
    if (!_isWeeklyScheduleQuery(q) ||
        q?.term == null ||
        !{
          FeatureLoadStatus.success,
          FeatureLoadStatus.empty,
          FeatureLoadStatus.stale,
        }.contains(widget.snapshot.status) ||
        !_sameQuery(widget.snapshot.readContext?.query, q) ||
        _weeks?.resolvedRoute == null ||
        _weeks?.resolvedRoute != widget.snapshot.resolvedRoute)
      return null;
    final matching = _weekCandidates(q!.term!)
        .where((d) => (d.presentation! as WeekPresentation).number == q.week)
        .toList();
    return matching.length == 1 ? matching.single : null;
  }

  Future<void> _loadMetadata(String term, int generation) async {
    try {
      final result = await widget.loadWeeks(term, false);
      if (!mounted ||
          !widget.visible ||
          generation != _generation ||
          widget.query?.term != term)
        return;
      if (result.error == null) {
        setState(() {
          _weeksTerm = term;
          _weeks = result;
        });
        _scheduleSync();
      }
    } on Object {
      // 元数据失败不覆盖已经成功的课表；按需面板保留明确重试入口。
    }
  }

  void _request(FeatureQuery query) {
    if (!mounted || !widget.visible) return;
    _expected = query;
    setState(() => _selectionNeeded = false);
    unawaited(widget.onQuery!(query));
  }

  void _needSelection(String? term) {
    _automatic = null;
    _expected = null;
    setState(() => _selectionNeeded = true);
    widget.adoptDraft(
      FeatureQuery(view: FeatureQueryView.scheduleWeek, term: term),
    );
  }

  @override
  Widget build(BuildContext context) => _ScheduleWeekScope(
    week: _visibleWeek?.presentation as WeekPresentation?,
    child: _selectionNeeded
        ? const Center(child: Text('请从右上角选择学期和教学周'))
        : !_started &&
              widget.query == null &&
              widget.onQuery != null &&
              widget.visible
        ? const Center(child: CircularProgressIndicator())
        : widget.child,
  );
}

class _ScheduleWeekScope extends InheritedWidget {
  const _ScheduleWeekScope({required this.week, required super.child});
  final WeekPresentation? week;
  static WeekPresentation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScheduleWeekScope>()?.week;
  @override
  bool updateShouldNotify(_ScheduleWeekScope old) => !identical(old.week, week);
}
