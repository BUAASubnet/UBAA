import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import 'editor.dart';
import 'format.dart';
import 'scope_boundary.dart';
import 'cache_status.dart';
import 'calendar_values.dart';
import 'month_calendar.dart';
import 'week_content.dart';
import 'list_content.dart';
import 'detail_content.dart';
part 'details.dart';
part 'export.dart';

enum AgendaViewMode { list, week, month }

class AgendaView extends StatefulWidget {
  const AgendaView({
    super.key,
    this.service,
    required this.scopeKey,
    required this.route,
    required this.term,
    required this.onOpenSchool,
    this.onSaveFile,
    this.onChanged,
    this.todoRequest = 0,
    this.visible = true,
    this.reminder,
    this.now,
    this.failure,
  });
  final AgendaService? service;
  final Object scopeKey;
  final ConnectionMode route;
  final String term;
  final ValueChanged<FeatureReadNavigation> onOpenSchool;
  final Future<String?> Function(
    AgendaExportResult result,
    String name,
    bool Function() isCurrent,
  )?
  onSaveFile;
  final VoidCallback? onChanged;
  final int todoRequest;
  final bool visible;
  final YgdkReminderSettings? reminder;
  final DateTime? now;
  final AgendaFailure? failure;
  @override
  State<AgendaView> createState() => AgendaViewState();
}

class AgendaViewState extends State<AgendaView> {
  AgendaQueryResult? result;
  String? error;
  bool loading = false,
      busy = false,
      includeCompleted = true,
      includeHidden = false;
  late bool todos;
  String filter = '全部', search = '';
  late DateTime from, to, focusDate;
  AgendaViewMode mode = AgendaViewMode.list;
  bool dayOnly = false, customRange = false;
  String? selectedKey;
  final searchField = TextEditingController();
  int revision = 0;
  final generation = ValueNotifier<int>(0);
  DateTime get now {
    final value = widget.now ?? campusDate(DateTime.now());
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  AgendaService get service => widget.service!;
  bool get available => widget.service?.accountId != null;
  bool current(int token) => mounted && token == revision && available;
  @override
  void initState() {
    super.initState();
    todos = widget.todoRequest > 0;
    focusDate = agendaDay(now);
    alignRange();
    if (widget.visible) unawaited(load());
  }

  @override
  void didUpdateWidget(covariant AgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey ||
        oldWidget.route != widget.route ||
        oldWidget.term != widget.term ||
        oldWidget.service != widget.service) {
      generation.value++;
      selectedKey = null;
      revision++;
      result = null;
      error = null;
      loading = false;
      busy = false;
      if (widget.visible) unawaited(load());
    } else if (!oldWidget.visible && widget.visible && result == null) {
      unawaited(load());
    }
    if (oldWidget.todoRequest != widget.todoRequest) todos = true;
  }

  @override
  void dispose() {
    generation.value++;
    searchField.dispose();
    super.dispose();
  }

  Widget bound(Widget child) =>
      AgendaScopeBoundary(generation: generation, child: child);
  AgendaQuery query({DateTime? start, DateTime? end, bool? hidden}) =>
      AgendaQuery(
        route: widget.route,
        term: widget.term,
        from: agendaDate(start ?? from),
        to: agendaDate(end ?? to),
        now: agendaTime(now),
        includeHidden: hidden ?? includeHidden,
        ygdkEnabled: widget.reminder?.enabled ?? true,
        ygdkWeekDone: false,
        ygdkTermDone: widget.reminder?.termDoneKey == widget.term,
      );
  void update(VoidCallback action) => setState(action);
  Future<void> load() async {
    final token = ++revision;
    if (!available) {
      setState(() {
        result = null;
        error = null;
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final month = agendaWeekStart(
        DateTime.utc(focusDate.year, focusDate.month),
      );
      final monthEnd = month.add(const Duration(days: 42));
      final value = await service.query(
        customRange
            ? query(hidden: true)
            : query(
                start: from.isBefore(month) ? from : month,
                end: to.isAfter(monthEnd) ? to : monthEnd,
                hidden: true,
              ),
      );
      if (current(token)) setState(() => result = value);
    } on Object {
      if (current(token))
        setState(() {
          result = null;
          error = '日程读取失败，原数据已保留';
        });
    } finally {
      if (mounted && token == revision) setState(() => loading = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (busy || !available) return;
    final token = revision;
    setState(() => busy = true);
    try {
      await action();
      if (!current(token)) return;
      widget.onChanged?.call();
      await load();
    } on Object {
      if (current(token))
        UbaaFeedback.show(context, '操作未完成，请重试', kind: UbaaFeedbackKind.error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit({
    AgendaItem? item,
    AgendaOccurrence? occurrence,
    AgendaEditScope scope = AgendaEditScope.all,
  }) async {
    if (busy || !available) return;
    final token = revision;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => bound(
          AgendaEditor(
            service: service,
            boundary: bound,
            isCurrent: () => current(token),
            item: item,
            occurrence: occurrence,
            scope: scope,
            now: now,
            findConflicts: (content) async {
              final start = agendaValue(content.start),
                  end = agendaValue(content.end);
              if (start == null || end == null) return [];
              final value = await service.query(
                query(
                  start: agendaDay(start),
                  end: agendaDay(end).add(const Duration(days: 1)),
                  hidden: true,
                ),
              );
              if (!current(token)) return [];
              return agendaContentConflicts(content, value.entries);
            },
          ),
        ),
      ),
    );
    if (current(token) && done == true) {
      widget.onChanged?.call();
      await load();
    }
  }

  bool accepts(AgendaEntry e) {
    if (!includeCompleted && e.completed || !includeHidden && e.hidden)
      return false;
    if (todos &&
        !(e.local?.content.kind == AgendaKind.task ||
            e.school?.homeTodo == true))
      return false;
    final source = agendaSource(e);
    if (filter != '全部' &&
        !(filter == '作业' ? source.contains('作业') : filter == source))
      return false;
    return '${agendaTitle(e)} ${e.note ?? ''} ${e.school?.subtitle ?? ''}'
        .toLowerCase()
        .contains(search.toLowerCase());
  }

  void alignRange() {
    if (mode == AgendaViewMode.list) {
      from = focusDate.subtract(const Duration(days: 7));
      to = from.add(const Duration(days: 38));
    } else if (mode == AgendaViewMode.week) {
      from = agendaWeekStart(focusDate);
      to = from.add(const Duration(days: 7));
    } else {
      from = DateTime.utc(focusDate.year, focusDate.month);
      to = DateTime.utc(focusDate.year, focusDate.month + 1);
    }
  }

  void goDate(DateTime date) {
    setState(() {
      focusDate = agendaDay(date);
      customRange = false;
      if (mode != AgendaViewMode.week) dayOnly = true;
      alignRange();
    });
    unawaited(load());
  }

  void goMode(AgendaViewMode value) {
    setState(() {
      mode = value;
      customRange = false;
      alignRange();
    });
    unawaited(load());
  }

  void move(int offset) {
    if (customRange) {
      setState(() {
        from = from.add(Duration(days: offset * 7));
        to = to.add(Duration(days: offset * 7));
        focusDate = focusDate.add(Duration(days: offset * 7));
      });
      unawaited(load());
    } else {
      goDate(
        mode == AgendaViewMode.month
            ? agendaShiftMonth(focusDate, offset)
            : focusDate.add(Duration(days: offset * 7)),
      );
    }
  }

  Widget filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: searchField,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: '搜索日程',
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        children: [
          for (final source in [
            '全部',
            '课程',
            '作业',
            '博雅',
            '考试',
            '研讨室',
            '签到',
            '阳光提醒',
            '我的',
          ])
            ChoiceChip(
              label: Text(source),
              selected: filter == source,
              onSelected: (_) => setState(() => filter = source),
            ),
        ],
      ),
      Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('待办'),
            selected: todos,
            onSelected: (v) => setState(() => todos = v),
          ),
          FilterChip(
            label: const Text('显示已完成'),
            selected: includeCompleted,
            onSelected: (v) => setState(() => includeCompleted = v),
          ),
          FilterChip(
            label: const Text('显示已隐藏'),
            selected: includeHidden,
            onSelected: (v) {
              setState(() => includeHidden = v);
              unawaited(load());
            },
          ),
        ],
      ),
    ],
  );

  List<Widget> notices() => [
    if (loading) const LinearProgressIndicator(),
    if (!available)
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.failure == null ? '登录本机账号后可使用日程' : '本机日程暂不可用，原数据已保留',
        ),
      ),
    if (error != null)
      Column(
        children: [
          Text(error!),
          TextButton(onPressed: load, child: const Text('重试读取')),
        ],
      ),
    if (result case final data?) ...[
      if (data.sources.every((s) => s.observations.isEmpty))
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('尚无学校缓存，本机事项可继续使用。学校数据请到原功能读取。'),
        )
      else if (data.schoolCacheFailure != null ||
          data.sources.any((s) => s.missingScopes.isNotEmpty))
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('部分学校缓存缺失，本机事项可继续使用。学校数据请到原功能读取。'),
        ),
      if (data.sources.any(
        (s) =>
            s.feature == AgendaFeature.schedule && s.semesterImported != true,
      ))
        const Text('尚未导入整学期课表，仅展示已缓存的教学周；可在课表中导入。'),
      AgendaCacheStatus(
        sources: data.sources,
        route: widget.route,
        now: agendaTime(now),
      ),
      if (data.sources.any((s) => s.unprojectableCount > 0))
        const Text('部分学校事项缺少必要字段，未加入时间线。'),
    ],
  ];

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: widget.visible,
    canRequestFocus: widget.visible,
    skipTraversal: true,
    descendantsAreFocusable: widget.visible,
    onKeyEvent: (node, event) {
      final editing =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() !=
          null;
      if (event is! KeyDownEvent ||
          !HardwareKeyboard.instance.isAltPressed ||
          editing)
        return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        move(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        move(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          1.4,
          MediaQuery.textScalerOf(context).scale(14) / 14,
        );
        final wide = constraints.maxWidth >= 1000 * scale;
        final detailPane = constraints.maxWidth >= 1420 * scale;
        final all = result?.entries ?? <AgendaEntry>[];
        final filtered = all.where(accepts).toList();
        final visible = filtered.where((entry) {
          final date = agendaEntryDate(entry);
          if (date == null) return true;
          final end = agendaEnd(entry), start = agendaStart(entry);
          return start != null && end != null
              ? agendaOverlaps(start, end, from, to)
              : !date.isBefore(from) && date.isBefore(to);
        }).toList();
        final list = mode == AgendaViewMode.month || dayOnly
            ? visible
                  .where(
                    (e) =>
                        agendaEntryDate(e) == null || agendaOnDay(e, focusDate),
                  )
                  .toList()
            : visible;
        void open(AgendaEntry entry) {
          if (detailPane) {
            setState(() => selectedKey = agendaEntryKey(entry));
          } else {
            unawaited(details(entry));
          }
        }

        final selected = (mode == AgendaViewMode.week ? visible : list)
            .where((e) => agendaEntryKey(e) == selectedKey)
            .firstOrNull;
        final content = RefreshIndicator(
          onRefresh: load,
          child: ListView(
            key: const ValueKey('agenda-main-scroll'),
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: !available || busy ? null : () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('新建事项'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !available || busy ? null : export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('导出日历'),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新本机数据'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<AgendaViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: AgendaViewMode.list,
                        label: Text('列表'),
                      ),
                      ButtonSegment(
                        value: AgendaViewMode.week,
                        label: Text('周'),
                      ),
                      ButtonSegment(
                        value: AgendaViewMode.month,
                        label: Text('月'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => goMode(v.single),
                  ),
                  TextButton(
                    onPressed: () => goDate(agendaDay(now)),
                    child: const Text('今天'),
                  ),
                  if (dayOnly && mode == AgendaViewMode.list)
                    TextButton(
                      onPressed: () => setState(() => dayOnly = false),
                      child: const Text('显示全部日期'),
                    ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: mode == AgendaViewMode.month ? '上一月' : '上一周',
                    onPressed: () => move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: range,
                      child: Text(
                        mode == AgendaViewMode.month
                            ? '${focusDate.year}年${focusDate.month}月'
                            : '${agendaDate(from)} 至 ${agendaDate(to.subtract(const Duration(days: 1)))}',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: mode == AgendaViewMode.month ? '下一月' : '下一周',
                    onPressed: () => move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (!wide && mode == AgendaViewMode.list)
                AgendaDateStrip(
                  date: focusDate,
                  entries: filtered,
                  onSelected: goDate,
                ),
              if (!wide) ...[filters(), const SizedBox(height: 8)],
              ...notices(),
              if (result != null && mode == AgendaViewMode.week)
                SizedBox(
                  height: math.max(440, constraints.maxHeight * .78),
                  child: AgendaWeekContent(
                    date: focusDate,
                    entries: visible,
                    allEntries: all,
                    onOpen: open,
                    onDate: goDate,
                  ),
                )
              else if (result != null) ...[
                if (mode == AgendaViewMode.month && !wide)
                  AgendaMonthCalendar(
                    date: focusDate,
                    entries: filtered,
                    onSelected: goDate,
                  ),
                if (mode == AgendaViewMode.month || dayOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${agendaDate(focusDate)} 的事项',
                      key: const ValueKey('agenda-selected-day'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                AgendaListContent(
                  entries: list,
                  allEntries: all,
                  now: now,
                  busy: busy,
                  onOpen: open,
                  onComplete: (e, v) => unawaited(complete(e, v)),
                ),
              ],
            ],
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) ...[
              SizedBox(
                width: 280 * scale,
                key: const ValueKey('agenda-sidebar'),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AgendaMonthCalendar(
                      date: focusDate,
                      entries: filtered,
                      onSelected: goDate,
                    ),
                    const SizedBox(height: 16),
                    filters(),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: content),
            if (detailPane) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320 * scale,
                key: const ValueKey('agenda-detail-pane'),
                child: selected == null
                    ? const Center(child: Text('选择事项查看详情'))
                    : detailContent(
                        selected,
                        () => setState(() => selectedKey = null),
                      ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Future<void> range() async {
    final token = revision;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: DateTime(from.year, from.month, from.day),
        end: DateTime(
          to.year,
          to.month,
          to.day,
        ).subtract(const Duration(days: 1)),
      ),
      builder: (_, child) => bound(child!),
    );
    if (!current(token) || selected == null) return;
    setState(() {
      from = agendaDay(selected.start);
      to = agendaDay(selected.end).add(const Duration(days: 1));
      focusDate = from;
      mode = AgendaViewMode.list;
      customRange = true;
      dayOnly = false;
    });
    await load();
  }
}
