import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../academic/content.dart' show uiSupportsAcademicContent;
import '../exam/timeline.dart' show uiAcademicSearchValues;
import 'cards.dart' show GradeCard, GradeSummaryCard;
import '../../shared/schedule_values.dart' show uiSavedScheduleTime;

/// 旧版两张统计卡和课程列表共用滚动区域，面板筛选不改变统计集合。
class GradesFlow extends StatefulWidget {
  const GradesFlow({
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
  final GradesAggregateLoader? loader;
  final ValueChanged<Map<String, ConnectionMode>>? onRoutes;
  @override
  State<GradesFlow> createState() => _GradesFlowState();
}

class _GradesFlowState extends State<GradesFlow> {
  GradesAggregate? _aggregate;
  bool _loading = false, _refreshAfterRead = false, uiScheduled = false;
  int _serial = 0;
  String? _selectedTermCode;
  String _localSearch = '';
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
  void didUpdateWidget(covariant GradesFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _serial++;
      _aggregate = null;
      _loading = false;
      _refreshAfterRead = false;
      _selectedTermCode = null;
      _localSearch = '';
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
    if (uiScheduled ||
        !widget.visible ||
        !_ready ||
        _loading ||
        widget.loader == null ||
        (_aggregate != null && !_refreshAfterRead))
      return;
    uiScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      uiScheduled = false;
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
      result = await loader(force, (value) {
        if (!mounted || serial != _serial) return;
        setState(() => _aggregate = value);
      });
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
      if (_ready)
        for (final term in aggregate?.terms ?? const <GradeTermRead>[])
          if (term.overview != null && term.resolvedRoute != null)
            '全部成绩 · ${term.name}': term.resolvedRoute!,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.visible) widget.onRoutes?.call(routes);
    });
    if ((!_ready && snapshot.status != FeatureLoadStatus.loading) ||
        current == null ||
        !uiSupportsAcademicContent(FeatureId.grades, snapshot.details))
      return widget.fallback;

    final terms = aggregate?.terms ?? const <GradeTermRead>[];
    final selectedCode = _selectedTermCode ?? current.termCode;
    var termIndex = terms.indexWhere((t) => t.code == selectedCode);
    if (termIndex == -1) termIndex = 0;
    final hasTerms = terms.length > 1;
    final activeTerm = hasTerms ? terms[termIndex] : null;
    final isCurrentTerm =
        activeTerm == null || activeTerm.code == current.termCode;
    final activeOverview = isCurrentTerm ? current : activeTerm.overview;
    final activeDetails = isCurrentTerm
        ? snapshot.details
        : activeTerm.result.details;
    final canPrev = hasTerms && termIndex > 0;
    final canNext = hasTerms && termIndex < terms.length - 1;

    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final localQ = _localSearch.trim().toLowerCase();
    final panelQ = widget.filter.trim().toLowerCase();
    final filter = localQ.isNotEmpty ? localQ : panelQ;

    final details = activeDetails
        .where(
          (detail) =>
              filter.isEmpty ||
              <String>[
                detail.title,
                if (detail.subtitle != null) detail.subtitle!,
                ...uiAcademicSearchValues(detail.presentation),
                for (final field in detail.fields) ...[
                  field.label,
                  field.value,
                ],
              ].any((value) => value.toLowerCase().contains(filter)),
        )
        .toList();
    return ListView(
      key: const PageStorageKey('grades-old-list'),
      padding: EdgeInsets.all(
        UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
      ),
      children: [
        if (snapshot.status == FeatureLoadStatus.stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('${snapshot.error?.message ?? '刷新失败。'} 以下为上次成功加载的数据。'),
          ),
        if (widget.loader != null || hasTerms) ...[
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一学期',
                    onPressed: canPrev
                        ? () => setState(
                            () => _selectedTermCode = terms[termIndex - 1].code,
                          )
                        : null,
                  ),
                  Expanded(
                    child: PopupMenuButton<String>(
                      tooltip: '选择学期',
                      enabled: hasTerms,
                      initialValue: selectedCode,
                      onSelected: (code) =>
                          setState(() => _selectedTermCode = code),
                      itemBuilder: (context) => [
                        for (final term in terms)
                          PopupMenuItem(
                            value: term.code,
                            child: Row(
                              children: [
                                if (term.code == selectedCode)
                                  Icon(
                                    Icons.check,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  )
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Text(term.name),
                                if (term.code == current.termCode)
                                  Text(
                                    ' (本学期)',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                isCurrentTerm
                                    ? '${activeTerm?.name ?? current.termCode} (本学期)'
                                    : activeTerm.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一学期',
                    onPressed: canNext
                        ? () => setState(
                            () => _selectedTermCode = terms[termIndex + 1].code,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (wide) ...[
          TextField(
            decoration: InputDecoration(
              hintText: '搜索课程名称/代码/教师/属性...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _localSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _localSearch = ''),
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (val) => setState(() => _localSearch = val),
          ),
          const SizedBox(height: 12),
        ],
        GradeSummaryCard(
          title: '全部成绩',
          statistics: aggregate?.statistics,
          loading: (_loading || widget.loader != null) && aggregate == null,
          notice: aggregate != null
              ? _gradesAggregateNotice(aggregate, _loading)
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
        if ((isCurrentTerm ? snapshot.evidence : activeTerm.result.evidence)
            case final evidence? when evidence.origin == DataOrigin.persisted)
          Text('此学期上次保存 ${_savedGradeTime(evidence.fetchedAt)}'),
        GradeSummaryCard(
          title: isCurrentTerm ? '本学期' : activeTerm.name,
          statistics: activeOverview != null
              ? GradeStatistics.calculate(activeOverview.grades)
              : null,
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
              child: GradeCard(detail: detail),
            ),
      ],
    );
  }
}

String? _gradesAggregateNotice(GradesAggregate aggregate, bool loading) {
  final lines = <String>[];
  if (aggregate.hasSavedData) {
    final times = [
      if (aggregate.termsEvidence case final evidence?) evidence.fetchedAt,
      for (final term in aggregate.terms)
        if (term.result.evidence case final evidence?) evidence.fetchedAt,
    ]..sort();
    lines.add(
      '已保存统计${times.isEmpty ? '' : ' · 最早保存 ${_savedGradeTime(times.first)}'}',
    );
    if (loading) lines.add('正在核对更新，仍可查看已保存成绩');
  }
  if (aggregate.error case final error?) lines.add(error.message);
  if (!aggregate.isComplete)
    lines.add(
      '部分统计 · 已读取 ${aggregate.loadedTerms}/${aggregate.terms.length} 个学期',
    );
  return lines.isEmpty ? null : lines.join('\n');
}

String _savedGradeTime(DateTime value) {
  final campus = value.toUtc().add(const Duration(hours: 8));
  return '${campus.year}年${uiSavedScheduleTime(value)}';
}
