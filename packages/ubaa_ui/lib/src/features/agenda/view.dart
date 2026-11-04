import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import 'editor.dart';
import 'format.dart';
import '../../shared/dialogs/scope_boundary.dart';
import 'cache_status.dart';
part 'details.dart';
part 'export.dart';

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
  late DateTime from, to;
  int revision = 0;
  final generation = ValueNotifier<int>(0);
  DateTime get now => widget.now ?? campusDate(DateTime.now());
  AgendaService get service => widget.service!;
  bool get available => widget.service?.accountId != null;
  bool current(int token) => mounted && token == revision && available;
  @override
  void initState() {
    super.initState();
    todos = widget.todoRequest > 0;
    from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 7));
    to = from.add(const Duration(days: 38));
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
    super.dispose();
  }

  Widget bound(Widget child) =>
      UiScopeBoundary(generation: generation, child: child);
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
      final value = await service.query(query());
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
            isCurrent: () => current(token),
            item: item,
            occurrence: occurrence,
            scope: scope,
            now: now,
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

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AgendaEntry>>{};
    for (final e in result?.entries.where(accepts) ?? <AgendaEntry>[]) {
      final date =
          e.timing.from ??
          (e.timing.start ?? e.timing.due ?? e.timing.end)?.rfc3339.substring(
            0,
            10,
          );
      final overdue =
          !e.completed &&
          e.timing.kind == AgendaTimingKind.deadline &&
          agendaValue(e.timing.due)?.isBefore(now) == true;
      final key = overdue ? '逾期待办' : date ?? '无日期';
      (groups[key] ??= []).add(e);
    }
    final keys = groups.keys.toList()
      ..sort(
        (a, b) => a == '逾期待办'
            ? -1
            : b == '逾期待办'
            ? 1
            : a.compareTo(b),
      );
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
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
          Row(
            children: [
              IconButton(
                tooltip: '上一周',
                onPressed: () {
                  from = from.subtract(const Duration(days: 7));
                  to = to.subtract(const Duration(days: 7));
                  unawaited(load());
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: range,
                  child: Text(
                    '${agendaDate(from)} 至 ${agendaDate(to.subtract(const Duration(days: 1)))}',
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一周',
                onPressed: () {
                  from = from.add(const Duration(days: 7));
                  to = to.add(const Duration(days: 7));
                  unawaited(load());
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          TextField(
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
                  s.feature == AgendaFeature.schedule &&
                  s.semesterImported != true,
            ))
              const Text('尚未导入整学期课表，仅展示已缓存的教学周；可在课表中导入。'),
            AgendaCacheStatus(
              sources: data.sources,
              route: widget.route,
              now: agendaTime(now),
            ),
            if (data.sources.any((s) => s.unprojectableCount > 0))
              const Text('部分学校事项缺少必要字段，未加入时间线。'),
            if (groups.isEmpty && !loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  '当前范围没有符合筛选的事项，可新建日程或待办',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final day in keys) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  day,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final e
                  in (groups[day]!..sort((a, b) {
                    final allA = a.timing.kind == AgendaTimingKind.allDay;
                    final allB = b.timing.kind == AgendaTimingKind.allDay;
                    return allA != allB
                        ? (allA ? -1 : 1)
                        : (a.sortTime?.rfc3339 ?? '').compareTo(
                            b.sortTime?.rfc3339 ?? '',
                          );
                  })))
                Card(
                  child: ListTile(
                    leading: Icon(
                      e.local == null
                          ? Icons.school_outlined
                          : e.local!.content.kind == AgendaKind.task
                          ? Icons.check_circle_outline
                          : Icons.event_outlined,
                      color: agendaColor(e.local?.content.color),
                    ),
                    title: Text(
                      agendaTitle(e),
                      style: TextStyle(
                        decoration: e.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      '${agendaSource(e)} · ${agendaWhen(e)}${e.hidden ? ' · 已隐藏' : ''}\n${e.local?.content.location ?? e.school?.location ?? ''}${e.note?.isNotEmpty == true ? ' · ${e.note}' : ''}',
                    ),
                    trailing:
                        e.school?.navigation.feature ==
                                AgendaFeature.schedule ||
                            e.school?.navigation.feature == AgendaFeature.exam
                        ? null
                        : Checkbox(
                            value: e.completed,
                            onChanged: busy ? null : (v) => complete(e, v!),
                          ),
                    onTap: () => details(e),
                    onLongPress: () => details(e),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> range() async {
    final token = revision;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: from,
        end: to.subtract(const Duration(days: 1)),
      ),
      builder: (_, child) => bound(child!),
    );
    if (!current(token) || selected == null) return;
    from = selected.start;
    to = selected.end.add(const Duration(days: 1));
    await load();
  }
}
