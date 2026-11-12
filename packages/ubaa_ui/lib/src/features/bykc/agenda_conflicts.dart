import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../agenda/format.dart';
import '../../shared/dialogs/scope_boundary.dart';

typedef BykcCourseWrite = Future<void> Function(WriteOperation, int);

/// 日程与选课共享账号和当前学期，投影变更后撤销旧检查。
final class BykcAgendaContext {
  BykcAgendaContext({
    required this.access,
    required this.route,
    required this.epoch,
  }) : accountGeneration = access.service?.accountGeneration;
  final AgendaAccess access;
  final ConnectionMode route;
  final Object epoch;
  final int? accountGeneration;
  Object get scope => (
    access.service,
    accountGeneration,
    access.failure,
    access.term,
    route,
    epoch,
  );
  bool get current => access.service?.accountGeneration == accountGeneration;
}

class BykcAgendaGuard extends StatefulWidget {
  const BykcAgendaGuard({
    super.key,
    required this.agenda,
    required this.details,
    required this.hideConflicts,
    required this.visible,
    required this.onWrite,
    required this.builder,
  });
  final BykcAgendaContext? agenda;
  final List<FeatureDetail> details;
  final bool hideConflicts, visible;
  final BykcCourseWrite? onWrite;
  final Widget Function(Set<int> hidden, bool busy, BykcCourseWrite? onWrite)
  builder;
  @override
  State<BykcAgendaGuard> createState() => _BykcAgendaGuardState();
}

class _BykcAgendaGuardState extends State<BykcAgendaGuard> {
  final _generation = ValueNotifier(0);
  Set<int> _hidden = const {};
  String? _notice;
  bool _checking = false, _selecting = false;

  List<BykcCoursePresentation> get _courses => [
    for (final detail in widget.details)
      if (detail.presentation case BykcCoursePresentation course)
        course
      else if (detail.presentation case BykcChosenPresentation chosen)
        if (chosen.fullDetail case final course?) course,
  ];
  List<(int, String?, String?)> _times(List<FeatureDetail> details) => [
    for (final detail in details)
      if (detail.presentation case BykcCoursePresentation course)
        (course.id, course.courseStartDate, course.courseEndDate),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant BykcAgendaGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged =
        oldWidget.agenda?.scope != widget.agenda?.scope ||
        oldWidget.visible != widget.visible ||
        oldWidget.hideConflicts != widget.hideConflicts;
    final oldTimes = _times(oldWidget.details), times = _times(widget.details);
    if (scopeChanged || !listEquals(oldTimes, times)) {
      _generation.value++;
      // 续载只追加课程时，已确认且时间未变的前页课程继续隐藏。
      _refresh(
        retained: scopeChanged
            ? const {}
            : {
                for (final time in times)
                  if (_hidden.contains(time.$1) && oldTimes.contains(time))
                    time.$1,
              },
      );
    }
  }

  @override
  void dispose() {
    _generation.value++;
    _generation.dispose();
    super.dispose();
  }

  bool _current(int token) =>
      mounted &&
      token == _generation.value &&
      widget.visible &&
      widget.agenda?.current != false;

  Future<AgendaQueryResult> _read(
    BykcAgendaContext config,
    List<BykcCourseInterval> intervals,
  ) {
    final service = config.access.service;
    if (service == null || config.access.failure != null || !config.current)
      throw const AgendaException(AgendaFailure.unavailable);
    final first = intervals
        .map((v) => v.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = intervals
        .map((v) => v.end)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return service.query(
      AgendaQuery(
        route: config.route,
        term: config.access.term,
        from: agendaDate(campusDate(first)),
        to: agendaDate(campusDate(last).add(const Duration(days: 1))),
        now: agendaTime(campusDate(clock.now())),
        includeHidden: false,
        ygdkEnabled: false,
        ygdkWeekDone: false,
        ygdkTermDone: false,
      ),
    );
  }

  bool _partial(AgendaQueryResult result) =>
      result.schoolCacheFailure != null ||
      result.sources.any(
        (source) =>
            const {
              AgendaFeature.schedule,
              AgendaFeature.exam,
              AgendaFeature.bykc,
              AgendaFeature.cgyy,
            }.contains(source.feature) &&
            (source.observations.isEmpty ||
                source.missingScopes.isNotEmpty ||
                source.unprojectableCount > 0 ||
                source.observations.any(
                  (v) =>
                      v.completeness == AgendaCompleteness.partial ||
                      !v.lastAttemptSucceeded,
                )),
      );

  void _refresh({Set<int> retained = const {}}) {
    _hidden = retained;
    _notice = null;
    _checking = false;
    if (!widget.visible || !widget.hideConflicts) return;
    final config = widget.agenda;
    if (config == null) {
      _notice = '日程暂不可用，尚未隐藏冲突课程';
      return;
    }
    final intervals = <int, BykcCourseInterval>{
      for (final course in _courses)
        if (BykcCourseInterval.parse(
              course.courseStartDate,
              course.courseEndDate,
            )
            case final interval?)
          course.id: interval,
    };
    if (intervals.isEmpty) return;
    final token = _generation.value;
    _checking = true;
    unawaited(() async {
      try {
        final result = await _read(config, intervals.values.toList());
        if (!_current(token)) return;
        setState(() {
          _hidden = {
            for (final entry in intervals.entries)
              if (bykcAgendaConflicts(
                entry.value,
                result.entries,
                courseId: entry.key,
              ).isNotEmpty)
                entry.key,
          };
          _notice = _partial(result) ? '日程信息不完整，只隐藏已确认冲突的课程' : null;
          _checking = false;
        });
      } on Object {
        if (_current(token))
          setState(() {
            _hidden = const {};
            _checking = false;
            _notice = '日程读取失败，尚未隐藏冲突课程';
          });
      }
    }());
  }

  Future<void> _write(WriteOperation operation, int id) async {
    final write = widget.onWrite;
    if (write == null || _selecting) return;
    if (operation != WriteOperation.bykcSelectCourse || widget.agenda == null)
      return write(operation, id);
    final token = _generation.value;
    final config = widget.agenda!;
    setState(() => _selecting = true);
    try {
      final course = _courses.where((v) => v.id == id).firstOrNull;
      final interval = BykcCourseInterval.parse(
        course?.courseStartDate,
        course?.courseEndDate,
      );
      List<AgendaEntry> conflicts = const [];
      String? message;
      if (interval == null) {
        message = '课程起止时间不完整，暂时无法检查日程冲突。';
      } else {
        try {
          final result = await _read(config, [interval]);
          conflicts = bykcAgendaConflicts(
            interval,
            result.entries,
            courseId: id,
          );
          if (_partial(result)) message = '部分日程信息尚未同步完整，检查仅包含已知时段。';
        } on Object {
          message = '日程读取失败，暂时无法检查时间冲突。';
        }
      }
      if (!_current(token)) return;
      if (conflicts.isNotEmpty || message != null) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => UiScopeBoundary(
            generation: _generation,
            child: AlertDialog(
              title: Text(conflicts.isEmpty ? '日程冲突检查未完成' : '与日程时间冲突'),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (course != null) Text(course.courseName),
                  for (final entry in conflicts)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('${agendaTitle(entry)}\n${_when(entry)}'),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(message),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('是否继续选课？'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('继续选课'),
                ),
              ],
            ),
          ),
        );
        if (proceed != true || !_current(token)) return;
      }
      await write(operation, id);
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  String _when(AgendaEntry entry) {
    final start = agendaValue(entry.timing.start ?? entry.local?.content.start);
    final end = agendaValue(entry.timing.end ?? entry.local?.content.end);
    if (entry.timing.kind == AgendaTimingKind.allDay)
      return '${start == null ? '' : agendaDate(start)} 全天';
    return '${start == null ? '' : '${agendaDate(start)} ${agendaHm(start)}'} — ${end == null ? '' : '${agendaDate(end)} ${agendaHm(end)}'}';
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_checking || _notice != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _checking ? '正在检查日程冲突…' : _notice!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (!_checking && _notice != null)
                TextButton(
                  onPressed: () => setState(() {
                    _generation.value++;
                    _refresh();
                  }),
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      Expanded(
        child: widget.builder(
          _hidden,
          _selecting,
          widget.onWrite == null ? null : _write,
        ),
      ),
    ],
  );
}
