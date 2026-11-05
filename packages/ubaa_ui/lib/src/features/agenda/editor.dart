import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

/// 编辑器只收集校园时区输入，重复规则由 Core 校验和展开。
class AgendaEditor extends StatefulWidget {
  const AgendaEditor({
    super.key,
    required this.service,
    required this.isCurrent,
    this.item,
    this.occurrence,
    this.scope = AgendaEditScope.all,
    required this.now,
    required this.boundary,
    this.findConflicts,
  });
  final AgendaService service;
  final bool Function() isCurrent;
  final AgendaItem? item;
  final AgendaOccurrence? occurrence;
  final AgendaEditScope scope;
  final DateTime now;
  final Widget Function(Widget) boundary;
  final Future<List<AgendaEntry>> Function(AgendaContent)? findConflicts;
  @override
  State<AgendaEditor> createState() => _AgendaEditorState();
}

class _AgendaEditorState extends State<AgendaEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  TextEditingController field(String key, String initial) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: initial));
  late AgendaKind _kind;
  late bool _allDay, _undated;
  String _repeat = '不重复';
  String _color = '#5B6FCB';
  TeachingWeekPattern _pattern = TeachingWeekPattern.every;
  int _weekday = 1;
  bool _busy = false;
  String? _error;
  String get initialSkips =>
      widget.item?.exdates.map((v) => v.rfc3339.substring(0, 10)).join(',') ??
      '';
  Set<String> skipDates(String value) =>
      value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet();
  AgendaContent? get original => widget.scope == AgendaEditScope.all
      ? widget.item?.content
      : widget.occurrence?.content;
  @override
  void initState() {
    super.initState();
    _kind = original?.kind ?? AgendaKind.event;
    _allDay = original?.allDay ?? false;
    _undated =
        original != null &&
        original!.kind == AgendaKind.task &&
        original!.due == null;
    _color = original?.color ?? _color;
    if (widget.item?.rrule != null) _repeat = '自定义';
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String initialTime(AgendaTime? value, DateTime fallback) => value == null
      ? '${agendaDate(fallback)} ${fallback.hour.toString().padLeft(2, '0')}:${fallback.minute.toString().padLeft(2, '0')}'
      : '${value.rfc3339.substring(0, 10)} ${value.rfc3339.substring(11, 16)}';
  DateTime parse(String key) {
    final value = _fields[key]!.text.trim();
    final date = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(value) ||
        initialTime(null, date) != value)
      throw const FormatException('时间格式应为 YYYY-MM-DD HH:mm');
    return date;
  }

  Widget text(
    String key,
    String label,
    String initial, {
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('agenda-$key'),
      controller: field(key, initial),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: lines,
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? '请填写$label' : null
          : null,
    ),
  );
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 日期/时间选择行：点按胶囊打开系统选择器，结果写回原有文本控制器，沿用既有解析与校验。
  Widget timeField(
    String key,
    String label,
    String initial, {
    bool dateOnly = false,
  }) {
    final controller = field(key, initial);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    DateTime current() =>
        DateTime.tryParse(controller.text.trim().replaceFirst(' ', 'T')) ??
        widget.now;
    void write(DateTime v) =>
        setState(() => controller.text = initialTime(null, v));
    Future<void> pickDate() async {
      final c = current();
      final picked = await showDatePicker(
        context: context,
        initialDate: c,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        builder: (_, child) => widget.boundary(child!),
      );
      if (picked == null || !mounted || !widget.isCurrent()) return;
      write(DateTime(picked.year, picked.month, picked.day, c.hour, c.minute));
    }

    Future<void> pickTime() async {
      final c = current();
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: c.hour, minute: c.minute),
        builder: (context, child) => widget.boundary(
          MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        ),
      );
      if (picked == null || !mounted || !widget.isCurrent()) return;
      write(DateTime(c.year, c.month, c.day, picked.hour, picked.minute));
    }

    Widget pill(String text, VoidCallback? onTap, String semantics, Key key) =>
        Semantics(
          button: true,
          label: '$label$semantics',
          excludeSemantics: true,
          child: Material(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        );
    final v = current();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 12,
        overflowSpacing: 8,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(
                '${v.month}月${v.day}日 周${_weekdays[v.weekday - 1]}',
                _busy ? null : pickDate,
                '日期',
                ValueKey('agenda-$key-date'),
              ),
              if (!dateOnly)
                pill(
                  '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}',
                  _busy ? null : pickTime,
                  '时间',
                  ValueKey('agenda-$key-time'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget section(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: children),
  );

  Future<void> save() async {
    if (!_form.currentState!.validate() || _busy || !widget.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      DateTime? start, end, due;
      if (_kind == AgendaKind.event) {
        start = parse('start');
        end = parse('end');
        if (_allDay) {
          start = DateTime(start.year, start.month, start.day);
          end = DateTime(end.year, end.month, end.day);
        }
        if (!end.isAfter(start))
          throw const FormatException('结束时间必须晚于开始时间，全天结束日期不包含在内');
      } else if (!_undated) {
        due = parse('due');
      }
      var anchor = start ?? due;
      String? rule = switch (_repeat) {
        '每天' => 'FREQ=DAILY',
        '每周' => 'FREQ=WEEKLY',
        '工作日' => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        '自定义' => field('rule', widget.item?.rrule ?? '').text.trim(),
        _ => null,
      };
      final exclusions = <AgendaTime>[];
      if (_repeat != '不重复' && anchor == null)
        throw const FormatException('重复待办需要截止时间');
      if (_repeat == '按教学周') {
        final generated = await widget.service.teachingWeekRule(
          TeachingWeekInput(
            monday: field('monday', '').text.trim(),
            first: int.parse(field('first', '1').text),
            last: int.parse(field('last', '18').text),
            pattern: _pattern,
            weekday: _weekday,
            hour: anchor!.hour,
            minute: anchor.minute,
            second: 0,
            skips: field('skips', '').text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
        );
        if (!mounted || !widget.isCurrent()) return;
        rule = generated.rrule;
        exclusions.addAll(generated.exdates);
        final next = agendaValue(generated.start)!;
        if (start != null) {
          end = next.add(end!.difference(start));
          start = next;
        } else {
          due = next;
        }
        anchor = next;
      } else if (_repeat != '不重复') {
        final skips = field('skips', '').text.trim();
        if (skips.isNotEmpty)
          for (final raw in skips.split(',')) {
            final day = DateTime.tryParse(raw.trim());
            if (day == null || agendaDate(day) != raw.trim() || anchor == null)
              throw const FormatException('排除日期使用 YYYY-MM-DD，以逗号分隔');
            exclusions.add(
              agendaTime(
                DateTime(
                  day.year,
                  day.month,
                  day.day,
                  anchor.hour,
                  anchor.minute,
                ),
              ),
            );
          }
      }
      final content = AgendaContent(
        kind: _kind,
        title: field('title', '').text.trim(),
        location: field('location', '').text.trim(),
        notes: field('notes', '').text.trim(),
        color: _color,
        allDay: _kind == AgendaKind.event && _allDay,
        start: start == null ? null : agendaTime(start),
        end: end == null ? null : agendaTime(end),
        due: due == null ? null : agendaTime(due),
      );
      final draft = AgendaDraft(
        content: content,
        rrule: rule?.isEmpty == true ? null : rule,
        exdates: exclusions,
      );
      if (!widget.isCurrent()) return;
      final conflicts =
          await widget.findConflicts?.call(content) ?? <AgendaEntry>[];
      if (!mounted || !widget.isCurrent()) return;
      if (conflicts.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => widget.boundary(
            AlertDialog(
              title: const Text('与已缓存课程重叠'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前发生与以下课程重叠，是否继续保存？'),
                    for (final course in conflicts)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${agendaTitle(course)} · ${agendaWhen(course)}',
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('返回修改'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('仍然保存'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || !widget.isCurrent() || confirmed != true) return;
      }
      if (widget.item == null) {
        await widget.service.create(
          draft,
          agendaTime(campusDate(DateTime.now())),
        );
      } else if (_repeat != '按教学周' &&
          rule != null &&
          setEquals(
            skipDates(field('skips', initialSkips).text),
            skipDates(initialSkips),
          )) {
        // 未修改的例外随系列一起由 Core 平移或拆分。
        await widget.service.edit(
          widget.item!.id,
          widget.scope,
          widget.occurrence == null ? null : recurrenceAt(widget.occurrence!),
          content,
          draft.rrule,
          agendaTime(campusDate(DateTime.now())),
        );
      } else {
        await widget.service.editDraft(
          widget.item!.id,
          widget.scope,
          widget.occurrence == null ? null : recurrenceAt(widget.occurrence!),
          draft,
          agendaTime(campusDate(DateTime.now())),
        );
      }
      if (mounted && widget.isCurrent()) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted && widget.isCurrent())
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : error is AgendaException &&
                    error.failure == AgendaFailure.invalidInput
              ? '时间或重复规则无效，请检查后保存'
              : '保存失败，原事项保持，请重试',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final content = original;
    final single =
        widget.item?.rrule != null &&
        widget.scope == AgendaEditScope.thisOccurrence;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? '新建事项' : '编辑事项'),
        centerTitle: false,
      ),
      body: Form(
        key: _form,
        child: ListView(
          key: const ValueKey('agenda-editor-list'),
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<AgendaKind>(
              segments: const [
                ButtonSegment(value: AgendaKind.event, label: Text('日程')),
                ButtonSegment(value: AgendaKind.task, label: Text('待办')),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() => _kind = v.single),
            ),
            const SizedBox(height: 20),
            text('title', '标题', content?.title ?? '', required: true),
            if (_kind == AgendaKind.event)
              section([
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('全天'),
                  value: _allDay,
                  onChanged: _busy ? null : (v) => setState(() => _allDay = v),
                ),
                const Divider(height: 1),
                timeField(
                  'start',
                  '开始',
                  initialTime(content?.start, now),
                  dateOnly: _allDay,
                ),
                timeField(
                  'end',
                  _allDay ? '结束（次日零点）' : '结束',
                  initialTime(content?.end, now.add(const Duration(hours: 1))),
                  dateOnly: _allDay,
                ),
              ])
            else
              section([
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('无日期待办'),
                  value: _undated,
                  onChanged: _busy ? null : (v) => setState(() => _undated = v),
                ),
                if (!_undated) ...[
                  const Divider(height: 1),
                  timeField(
                    'due',
                    '截止',
                    initialTime(
                      content?.due,
                      now.add(const Duration(hours: 1)),
                    ),
                  ),
                ],
              ]),
            if (!single) ...[
              DropdownButtonFormField<String>(
                initialValue: _repeat,
                decoration: const InputDecoration(labelText: '重复'),
                items: [
                  for (final s in ['不重复', '每天', '每周', '工作日', '按教学周', '自定义'])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _repeat = v!),
              ),
              const SizedBox(height: 16),
              if (_repeat == '自定义')
                text(
                  'rule',
                  'RRULE（如 FREQ=MONTHLY;BYMONTHDAY=15）',
                  widget.item?.rrule ?? '',
                ),
              if (_repeat == '按教学周') ...[
                text(
                  'monday',
                  '第一教学周周一（YYYY-MM-DD）',
                  agendaDate(now.subtract(Duration(days: now.weekday - 1))),
                ),
                Row(
                  children: [
                    Expanded(child: text('first', '开始教学周', '1')),
                    const SizedBox(width: 12),
                    Expanded(child: text('last', '结束教学周', '18')),
                  ],
                ),
                DropdownButtonFormField<TeachingWeekPattern>(
                  initialValue: _pattern,
                  decoration: const InputDecoration(labelText: '教学周范围'),
                  items: const [
                    DropdownMenuItem(
                      value: TeachingWeekPattern.every,
                      child: Text('每周'),
                    ),
                    DropdownMenuItem(
                      value: TeachingWeekPattern.odd,
                      child: Text('单周'),
                    ),
                    DropdownMenuItem(
                      value: TeachingWeekPattern.even,
                      child: Text('双周'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _pattern = v!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _weekday,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: [
                    for (var d = 1; d <= 7; d++)
                      DropdownMenuItem(
                        value: d,
                        child: Text('星期${'一二三四五六日'[d - 1]}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _weekday = v!),
                ),
              ],
              if (_repeat != '不重复')
                text('skips', '跳过日期 / 假期（逗号分隔）', initialSkips),
            ],
            text('location', '地点', content?.location ?? ''),
            text('notes', '备注', content?.notes ?? '', lines: 3),
            DropdownButtonFormField<String>(
              initialValue: _color,
              decoration: const InputDecoration(labelText: '颜色'),
              items: [
                for (final c in {
                  '#5B6FCB': '蓝紫',
                  '#30856A': '绿色',
                  '#C77A29': '橙色',
                  '#BA4F65': '玫红',
                  if (![
                    '#5B6FCB',
                    '#30856A',
                    '#C77A29',
                    '#BA4F65',
                  ].contains(_color))
                    _color: '原颜色',
                }.entries)
                  DropdownMenuItem(value: c.key, child: Text(c.value)),
              ],
              onChanged: (v) => setState(() => _color = v!),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              '所有时间均为北京时间。重复事项按校园时区展开。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: FilledButton(
          key: const ValueKey('agenda-editor-save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _busy ? null : save,
          child: Text(_busy ? '保存中…' : '保存事项'),
        ),
      ),
    );
  }
}
