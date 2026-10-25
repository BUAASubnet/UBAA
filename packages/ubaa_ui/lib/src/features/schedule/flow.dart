import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import '../../shared/loading.dart' show LoadingPlaceholder;
import '../../shared/refresh.dart' show RefreshViewport;
import '../../common/error_card.dart' show FriendlyErrorCard;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'import.dart' show ScheduleRefreshError;
import 'colors.dart' show ScheduleCourseColors;
import 'week_picker.dart' show AcademicWeekDialog;
import '../academic/terms.dart' show AcademicTermDialog;
import '../../shared/schedule_values.dart' show uiIsWeeklyScheduleQuery;

enum _ScheduleAutoStage { terms, weeks, week }

/// 使用现有可见查询状态推进旧版选择顺序；每一步实际路线仍由该快照提供。
class ScheduleFlow extends StatefulWidget {
  const ScheduleFlow({
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
    this.loadTerms,
    this.imports = const {},
    this.onSave,
    this.onCancelImport,
  });
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final bool visible;
  final int epoch;
  final Future<FeatureResult> Function(String, bool) loadWeeks;
  final Future<void> Function(FeatureQuery)? onQuery;
  final ValueChanged<FeatureQuery> adoptDraft;
  final ValueChanged<String?>? onTitle;
  final Future<FeatureResult> Function(bool)? loadTerms;
  final Widget child;
  final Map<String, ScheduleImportState> imports;
  final Future<void> Function(String)? onSave;
  final ValueChanged<String>? onCancelImport;
  @override
  State<ScheduleFlow> createState() => ScheduleFlowState();
}

class ScheduleFlowState extends State<ScheduleFlow> {
  _ScheduleAutoStage? _automatic;
  FeatureQuery? _expected;
  bool _started = false, _selectionNeeded = false, _selectingTerm = false;
  int _generation = 0;
  String? _weeksTerm, _metadataAttempt, _reportedTitle;
  FeatureResult? _weeks;
  final _downloadAttempts = <String>{};
  final _courseColors = <String, ScheduleCourseColors>{};
  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant ScheduleFlow old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch) {
      _generation++;
      _downloadAttempts.clear();
      _courseColors.clear();
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

  bool get _hasSavedRead =>
      widget.snapshot.evidence?.origin == DataOrigin.persisted &&
      widget.snapshot.evidence?.complete == true;

  bool get _settled =>
      ({
            FeatureLoadStatus.success,
            FeatureLoadStatus.empty,
          }.contains(widget.snapshot.status) ||
          (_hasSavedRead &&
              {
                FeatureLoadStatus.loading,
                FeatureLoadStatus.stale,
              }.contains(widget.snapshot.status))) &&
      _sameQuery(widget.snapshot.readContext?.query, widget.query);

  void _sync() {
    if (!widget.visible || widget.onQuery == null || _selectingTerm) return;
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
        evidence: widget.snapshot.evidence,
      );
    }
    _downloadSemester();
    if ((_automatic == _ScheduleAutoStage.terms ||
            _automatic == _ScheduleAutoStage.weeks) &&
        _sameQuery(_expected, widget.query) &&
        widget.snapshot.status == FeatureLoadStatus.stale &&
        !_hasSavedRead &&
        widget.snapshot.error == null) {
      _needSelection(widget.query?.term);
      return;
    }
    if (_automatic == _ScheduleAutoStage.week &&
        _sameQuery(_expected, widget.query) &&
        (_settled ||
            (widget.snapshot.status == FeatureLoadStatus.stale &&
                _sameQuery(
                  widget.snapshot.readContext?.query,
                  widget.query,
                )))) {
      setState(() => _automatic = null);
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
      _automatic = _ScheduleAutoStage.week;
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
        uiIsWeeklyScheduleQuery(query) &&
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

  void _downloadSemester() {
    final term = widget.query?.term;
    if (!_settled ||
        term == null ||
        term.trim().isEmpty ||
        widget.onSave == null ||
        !(widget.query?.view == FeatureQueryView.scheduleWeeks ||
            uiIsWeeklyScheduleQuery(widget.query)) ||
        widget.imports.containsKey(term) ||
        !_downloadAttempts.add(term))
      return;
    unawaited(_startDownload(term, widget.epoch));
  }

  Future<void> _startDownload(String term, int epoch) async {
    try {
      await widget.onSave!(term);
    } on Object {
      if (mounted &&
          widget.visible &&
          widget.epoch == epoch &&
          widget.query?.term == term) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刷新失败，请稍后重试')));
      }
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
    if (!uiIsWeeklyScheduleQuery(q) ||
        q?.term == null ||
        !{
          FeatureLoadStatus.success,
          FeatureLoadStatus.empty,
          FeatureLoadStatus.stale,
          if (_hasSavedRead) FeatureLoadStatus.loading,
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

  Future<void> selectTerm() async {
    final loader = widget.loadTerms;
    if (!widget.visible ||
        loader == null ||
        widget.onQuery == null ||
        _selectingTerm)
      return;
    setState(() => _selectingTerm = true);
    final generation = _generation;
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => AcademicTermDialog(
        loader: loader,
        selected: widget.query?.term ?? '',
      ),
    );
    if (!mounted) return;
    setState(() => _selectingTerm = false);
    if (!widget.visible || generation != _generation) {
      _scheduleSync();
      return;
    }
    if (selected == null || selected == widget.query?.term) {
      _scheduleSync();
      return;
    }
    stopAutomatic(notify: false);
    _automatic = _ScheduleAutoStage.weeks;
    _request(
      FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: selected),
    );
  }

  Future<void> _openWeekDialog(BuildContext context, String term) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => AcademicWeekDialog(
        term: term,
        selected: widget.query?.week,
        loader: (force) => widget.loadWeeks(term, force),
      ),
    );
    if (!mounted || selected == null) return;
    _request(
      FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: term,
        week: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 自动定位索引只参与选择，不作为正文交付到屏幕。
    final firstFrame =
        !_started && widget.query == null && widget.onQuery != null;
    final failed =
        _sameQuery(widget.snapshot.readContext?.query, widget.query) &&
        (widget.snapshot.status == FeatureLoadStatus.failure ||
            (widget.snapshot.status == FeatureLoadStatus.stale &&
                widget.snapshot.error != null &&
                !_hasSavedRead));
    if (firstFrame || (_automatic != null && !failed)) {
      return const RefreshViewport(child: LoadingPlaceholder());
    }
    final indexQuery = {
      FeatureQueryView.scheduleTerms,
      FeatureQueryView.scheduleWeeks,
    }.contains(widget.query?.view);
    if (indexQuery && failed && widget.snapshot.error != null) {
      return RefreshViewport(
        child: Center(
          child: FriendlyErrorCard(
            error: widget.snapshot.error!,
            onRetry: widget.onQuery == null
                ? null
                : () => _request(widget.query!),
          ),
        ),
      );
    }
    if (_automatic != null && failed) return widget.child;
    final term = widget.query?.term ?? _weeksTerm;
    final candidates = term != null
        ? _weekCandidates(term)
        : const <FeatureDetail>[];
    final currentWeekNum =
        widget.query?.week ??
        (_visibleWeek?.presentation as WeekPresentation?)?.number;
    final currentIndex = candidates.indexWhere(
      (d) => (d.presentation as WeekPresentation).number == currentWeekNum,
    );
    final prevWeek = currentIndex > 0
        ? (candidates[currentIndex - 1].presentation as WeekPresentation).number
        : (currentWeekNum != null && currentWeekNum > 1
              ? currentWeekNum - 1
              : null);
    final nextWeek = currentIndex >= 0 && currentIndex < candidates.length - 1
        ? (candidates[currentIndex + 1].presentation as WeekPresentation).number
        : (currentWeekNum != null ? currentWeekNum + 1 : null);

    final weekHeader = Padding(
      padding: UbaaTheme.pageInsets(context, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: '上一周',
            icon: const Icon(Icons.chevron_left),
            onPressed: prevWeek == null || widget.onQuery == null
                ? null
                : () => _request(
                    FeatureQuery(
                      view: FeatureQueryView.scheduleWeek,
                      term: term,
                      week: prevWeek,
                    ),
                  ),
          ),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: term == null ? null : () => _openWeekDialog(context, term),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _visibleWeek?.title ??
                            (currentWeekNum != null
                                ? '第 $currentWeekNum 周'
                                : '选择周次'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            icon: const Icon(Icons.chevron_right),
            onPressed: nextWeek == null || widget.onQuery == null
                ? null
                : () => _request(
                    FeatureQuery(
                      view: FeatureQueryView.scheduleWeek,
                      term: term,
                      week: nextWeek,
                    ),
                  ),
          ),
        ],
      ),
    );

    Widget content;
    if (_selectionNeeded || indexQuery) {
      content = RefreshViewport(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(term == null ? '请选择学期' : '请选择教学周'),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.calendar_view_week),
                label: Text(term == null ? '选择学期' : '选择教学周'),
                onPressed: term == null
                    ? selectTerm
                    : () => _openWeekDialog(context, term),
              ),
            ],
          ),
        ),
      );
    } else {
      content = widget.child;
    }

    return ScheduleWeekScope(
      colors: _courseColors.putIfAbsent(term ?? '', ScheduleCourseColors.new),
      week: _visibleWeek?.presentation as WeekPresentation?,
      child: Column(
        children: [
          if (term != null) weekHeader,
          if (term != null && widget.onSave != null)
            ScheduleRefreshError(
              term: term,
              state: widget.imports[term],
              onRefresh: widget.onSave!,
            ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class ScheduleWeekScope extends InheritedWidget {
  const ScheduleWeekScope({
    required this.week,
    required super.child,
    this.colors,
  });
  final ScheduleCourseColors? colors;
  static ScheduleCourseColors? colorsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleWeekScope>()?.colors;
  final WeekPresentation? week;
  static WeekPresentation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleWeekScope>()?.week;
  @override
  bool updateShouldNotify(ScheduleWeekScope old) =>
      !identical(old.colors, colors) || !identical(old.week, week);
}
