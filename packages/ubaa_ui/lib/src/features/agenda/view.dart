import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import 'editor.dart';
import 'format.dart';
import '../../shared/dialogs/scope_boundary.dart';
import 'cache_status.dart';
import 'calendar_values.dart';
import 'month_calendar.dart';
import 'week_content.dart';
import 'list_content.dart';
import 'sync_status.dart';
import 'detail_content.dart';
import '../../shared/create_button.dart';
import '../../shared/loading.dart';
import '../../shared/refresh.dart';
import '../../common/state_panel.dart';
part 'details.dart';
part 'export.dart';
part 'filters.dart';
part 'toolbar.dart';
part 'data_sheet.dart';

enum AgendaViewMode { list, week, month }

class AgendaView extends StatefulWidget {
  const AgendaView({
    super.key,
    this.service,
    required this.scopeKey,
    this.projectionKey,
    this.syncScopeKey,
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
    this.onRefreshSchool,
    this.onImportSchedule,
  });
  final AgendaService? service;
  final Object scopeKey;
  final Object? projectionKey;
  final Object? syncScopeKey;
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
  final Future<void> Function()? onRefreshSchool;
  final VoidCallback? onImportSchedule;
  @override
  State<AgendaView> createState() => AgendaViewState();
}

class AgendaViewState extends State<AgendaView> {
  AgendaQueryResult? result;
  String? error;
  bool loading = false,
      pulling = false,
      busy = false,
      includeCompleted = true,
      includeHidden = false;
  late bool todos;
  String filter = '全部', search = '';
  late DateTime from, to, focusDate;
  AgendaViewMode mode = AgendaViewMode.list;
  bool dayOnly = false, customRange = false;
  bool searchVisible = false, noticesDismissed = false;
  String? selectedKey;
  final searchField = TextEditingController();
  int revision = 0;
  final generation = ValueNotifier<int>(0);

  /// 每次日程页重建后递增，供打开中的底部面板同步刷新。
  final sheetTick = ValueNotifier<int>(0);
  StreamSubscription<AgendaSyncState>? _syncSubscription;
  Object? _lastSyncKey;
  late Object _scope;
  bool _projectionDirty = false;

  Object get _liveScope => (
    widget.service,
    widget.service?.accountGeneration,
    widget.scopeKey,
    widget.syncScopeKey,
    widget.route,
    widget.term,
  );

  bool _refreshScope() {
    final next = _liveScope;
    if (_scope == next) return false;
    _scope = next;
    generation.value++;
    selectedKey = null;
    revision++;
    result = null;
    error = null;
    loading = false;
    busy = false;
    _projectionDirty = true;
    return true;
  }

  void _invalidateProjection() {
    _projectionDirty = true;
    if (widget.visible) {
      unawaited(load());
    } else {
      revision++;
    }
  }

  void _listenSync() {
    unawaited(_syncSubscription?.cancel());
    final watched = widget.service;
    _syncSubscription = watched?.syncUpdates.listen((state) {
      if (!mounted || !identical(watched, widget.service)) return;
      if (_refreshScope()) {
        if (widget.visible) unawaited(load());
        _pullSync();
        return;
      }
      // 上传失败时，前面的只读合并也可能已落库。
      if (available &&
          !state.running &&
          (state.error != null || (state.report?.changedCount ?? 0) > 0)) {
        widget.onChanged?.call();
        _invalidateProjection();
      }
    });
  }

  void _pullSync() {
    if (!widget.visible ||
        !available ||
        !service.supportsSync ||
        !service.syncEnabled)
      return;
    final key = (
      widget.service,
      service.accountGeneration,
      widget.syncScopeKey,
      widget.route,
    );
    if (_lastSyncKey == key) return;
    _lastSyncKey = key;
    unawaited(
      service
          .sync(AgendaSyncAction.pull, agendaTime(now))
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

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
  bool current(int token) =>
      mounted && token == generation.value && available && _scope == _liveScope;
  @override
  void initState() {
    super.initState();
    todos = widget.todoRequest > 0;
    focusDate = agendaDay(now);
    alignRange();
    _scope = _liveScope;
    _listenSync();
    if (widget.visible) unawaited(load());
    _pullSync();
  }

  @override
  void didUpdateWidget(covariant AgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameVisible = !oldWidget.visible && widget.visible;
    if (becameVisible) _lastSyncKey = null;
    if (oldWidget.service != widget.service) _listenSync();
    if (_refreshScope() || oldWidget.projectionKey != widget.projectionKey) {
      _invalidateProjection();
    } else if (becameVisible && (_projectionDirty || result == null)) {
      unawaited(load());
    }
    if (oldWidget.todoRequest != widget.todoRequest) _showAllTodos();
    _pullSync();
  }

  /// 首页「查看全部」：清除遗留筛选与搜索，回到列表并显示全部待办。
  void _showAllTodos() {
    todos = true;
    filter = '全部';
    search = '';
    searchField.clear();
    searchVisible = false;
    dayOnly = false;
    customRange = false;
    mode = AgendaViewMode.list;
    focusDate = agendaDay(now);
    alignRange();
    if (widget.visible) unawaited(load());
  }

  @override
  void dispose() {
    generation.value++;
    sheetTick.dispose();
    unawaited(_syncSubscription?.cancel());
    searchField.dispose();
    super.dispose();
  }

  Widget bound(Widget child) =>
      UiScopeBoundary(generation: generation, child: child);
  Widget _syncStatusCard() {
    final token = generation.value;
    return AgendaSyncStatusCard(
      service: service,
      now: agendaTime(now),
      boundary: bound,
      isCurrent: () => current(token),
    );
  }

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
  void update(VoidCallback action) {
    final wasTodos = todos;
    setState(action);
    // 待办列表的范围更长，切换时重新对齐并读取。
    if (wasTodos != todos && mode == AgendaViewMode.list && !customRange) {
      setState(alignRange);
      unawaited(load());
    }
  }

  Future<void> load() async {
    final token = ++revision;
    final scopeToken = generation.value;
    bool queryCurrent() => current(scopeToken) && token == revision;
    _projectionDirty = false;
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
      if (queryCurrent()) setState(() => result = value);
    } on Object {
      if (queryCurrent())
        setState(() {
          result = null;
          error = '日程读取失败，原数据已保留';
        });
    } finally {
      if (queryCurrent()) setState(() => loading = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (busy || !available) return;
    final token = generation.value;
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
      if (current(token)) setState(() => busy = false);
    }
  }

  Future<void> edit({
    AgendaItem? item,
    AgendaOccurrence? occurrence,
    AgendaEditScope scope = AgendaEditScope.all,
  }) async {
    if (busy || !available) return;
    final token = generation.value;
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
      from = focusDate;
      // 只看待办时覆盖首页待办可能出现的远期截止，与首页数量一致。
      to = from.add(Duration(days: todos ? 180 : 38));
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
      // 待办只有截止时刻，周、月网格里几乎为空；离开列表时退回全部。
      if (value != AgendaViewMode.list) todos = false;
      mode = value;
      customRange = false;
      alignRange();
    });
    unawaited(load());
  }

  void move(int offset) {
    setState(() {
      focusDate = mode == AgendaViewMode.month
          ? agendaShiftMonth(focusDate, offset)
          : focusDate.add(Duration(days: offset * 7));
      if (customRange) {
        from = from.add(Duration(days: offset * 7));
        to = to.add(Duration(days: offset * 7));
      } else {
        alignRange();
      }
    });
    unawaited(load());
  }

  int get selectedFilterCount =>
      (filter == '全部' ? 0 : 1) +
      (todos ? 1 : 0) +
      (includeCompleted ? 0 : 1) +
      (includeHidden ? 1 : 0);

  Widget filters({VoidCallback? onUpdate}) => _buildFilters(onUpdate: onUpdate);

  Future<void> showFilters() => _showFilters();

  void importSchedule() {
    if (widget.onImportSchedule case final action?) {
      action();
    } else {
      widget.onOpenSchool(
        FeatureReadNavigation(
          feature: FeatureId.schedule,
          query: FeatureQuery(term: widget.term),
        ),
      );
    }
  }

  bool schoolRefreshing = false;

  Future<void> refreshSchool() async {
    if (widget.onRefreshSchool case final action?) {
      if (schoolRefreshing) return;
      setState(() => schoolRefreshing = true);
      try {
        await action();
        if (mounted) await load();
      } finally {
        if (mounted) setState(() => schoolRefreshing = false);
      }
    } else {
      importSchedule();
    }
  }

  Widget toolbar() => _buildToolbar();

  String get rangeLabel {
    if (mode == AgendaViewMode.month)
      return '${focusDate.year}年${focusDate.month}月';
    final start = customRange ? from : agendaWeekStart(focusDate);
    final end = customRange
        ? to.subtract(const Duration(days: 1))
        : start.add(const Duration(days: 6));
    return '${start.month}月${start.day}日–${start.month == end.month ? '' : '${end.month}月'}${end.day}日';
  }

  bool get _onToday => mode == AgendaViewMode.month
      ? focusDate.year == agendaDay(now).year &&
            focusDate.month == agendaDay(now).month
      : agendaWeekStart(focusDate) == agendaWeekStart(agendaDay(now)) &&
            (mode == AgendaViewMode.week || focusDate == agendaDay(now));

  Widget viewControls() => _buildViewControls();

  static const _quickFilters = [
    '全部',
    '待办',
    '课程',
    '作业',
    '考试',
    '博雅',
    '研讨室',
    '签到',
    '阳光打卡',
    '我的',
  ];

  Widget quickFilters() => _buildQuickFilters();

  Future<void> dataSheet() => _showDataSheet();

  Widget statusLine() => _buildStatusLine();

  List<Widget> notices() => [
    if (!available)
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text(widget.failure == null ? '登录后可使用日程' : '日程暂时无法打开，数据未丢失'),
      ),
    if (error != null)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: UiInlineRetry(message: error!, onRetry: load),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sheetTick.value++;
    });
    return _buildView(context);
  }

  Widget _buildView(BuildContext context) => Focus(
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
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (searchVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  key: const ValueKey('agenda-search'),
                  controller: searchField,
                  autoFocus: true,
                  hintText: '搜索标题、备注或地点',
                  elevation: const WidgetStatePropertyAll(0),
                  leading: const Icon(Icons.search),
                  trailing: [
                    IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        searchField.clear();
                        setState(() => search = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                  onChanged: (value) => setState(() => search = value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: viewControls(),
            ),
            if (!wide && mode == AgendaViewMode.list)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: AgendaDateStrip(
                  date: focusDate,
                  today: agendaDay(now),
                  entries: filtered,
                  onSelected: goDate,
                  onSwipe: move,
                  colorOf: (e) =>
                      agendaSourceColor(e, Theme.of(context).colorScheme),
                ),
              ),
            if (!wide) quickFilters(),
            if (available) statusLine(),
            ...notices(),
            const SizedBox(height: 6),
            // 只有首次读取在页面内提示；刷新进度显示在标题栏右侧。
            SizedBox(
              height: 2,
              child: loading && result == null
                  ? const LinearProgressIndicator()
                  : null,
            ),
          ],
        );
        final fillsWeek = constraints.maxHeight >= 640;
        final week = AgendaWeekContent(
          key: const ValueKey('agenda-week-content'),
          date: focusDate,
          entries: visible,
          allEntries: all,
          onOpen: open,
          onDate: goDate,
        );
        final content = PullToRefresh(
          onRefresh: () async {
            setState(() => pulling = true);
            try {
              await load();
            } finally {
              if (mounted) setState(() => pulling = false);
            }
          },
          child: CustomScrollView(
            key: const ValueKey('agenda-main-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (result != null && mode == AgendaViewMode.week)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // 周网格撑满到底栏；矮窗口保留最小高度，整页可滚动。
                  sliver: fillsWeek
                      ? SliverFillRemaining(child: week)
                      : SliverToBoxAdapter(
                          child: SizedBox(height: 440, child: week),
                        ),
                )
              else if (result != null) ...[
                if (mode == AgendaViewMode.month && !wide)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: AgendaMonthCalendar(
                        date: focusDate,
                        entries: filtered,
                        onSelected: goDate,
                        today: agendaDay(now),
                        colorOf: (e) =>
                            agendaSourceColor(e, Theme.of(context).colorScheme),
                      ),
                    ),
                  ),
                ...agendaListSlivers(
                  context: context,
                  entries: list,
                  allEntries: all,
                  now: now,
                  busy: busy,
                  onOpen: open,
                  onComplete: (e, v) => unawaited(complete(e, v)),
                  onCreate: available && !busy ? () => edit() : null,
                  compactEmpty: mode == AgendaViewMode.month
                      ? '${agendaMonthDay(focusDate)} 没有安排'
                      : null,
                ),
              ],
              if (!(fillsWeek && mode == AgendaViewMode.week))
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          ),
        );
        return Column(
          children: [
            toolbar(),
            Expanded(
              child: Stack(
                children: [
                  Row(
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
                                today: agendaDay(now),
                                colorOf: (e) => agendaSourceColor(
                                  e,
                                  Theme.of(context).colorScheme,
                                ),
                              ),
                              const SizedBox(height: 16),
                              filters(),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            Expanded(child: content),
                          ],
                        ),
                      ),
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
                  ),
                  ubaaPositionedCreateButton(
                    key: const ValueKey('agenda-create'),
                    tooltip: '新建事项',
                    onPressed: !available || busy ? null : () => edit(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> range() async {
    final token = generation.value;
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
