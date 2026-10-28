import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../../shared/loading.dart' show LoadingPlaceholder;
import '../../common/error_card.dart' show FriendlyErrorCard;
import 'reservation_table.dart' show CgyyTableHeader;
import '../../write/cgyy/draft.dart' show CgyyFormContext;
import '../../write/cgyy/form.dart'
    show uiCgyyActionKey, uiCollectCgyyReservation, uiSelectCgyyAction;
part 'table.dart';
part 'choices.dart';
part 'selection_bar.dart';

class CgyyReservationFlow extends StatefulWidget {
  const CgyyReservationFlow({
    required this.snapshot,
    required this.query,
    required this.cacheEpoch,
    required this.fallback,
    required this.onQuery,
    this.onSubmit,
    required this.formContext,
    super.key,
    required this.onRetry,
    this.onlyAvailable = true,
    this.onShowAll,
  });

  /// 由顶栏开关控制，切换日期或楼层时保持。
  final bool onlyAvailable;
  final VoidCallback? onShowAll;
  final FeatureSnapshot snapshot;
  final FeatureQuery query;
  final int cacheEpoch;
  final Widget fallback;
  final Future<void> Function(FeatureQuery)? onQuery;
  final CgyyReservationStarter? onSubmit;
  final CgyyFormContext formContext;
  final Future<void> Function() onRetry;
  @override
  State<CgyyReservationFlow> createState() => CgyyReservationFlowState();
}

class CgyyReservationFlowState extends State<CgyyReservationFlow> {
  List<CgyySitePresentation> _sites = [];
  String _campus = '全部';
  int? _site;
  final _selected = <String>{};
  // 切换日期或楼层时保留上一张表，避免整页闪成加载圈。
  FeatureSnapshot? _lastDaySnapshot;
  FeatureSnapshot? _consumed;
  int _generation = 0;
  int? _afterRevision;
  bool _pending = false;
  final _headerTimes = ScrollController();
  final _bodyTimes = ScrollController();
  bool _syncingTimes = false;

  void _syncTimes(ScrollController source, ScrollController target) {
    if (_syncingTimes || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - offset).abs() < .01) return;
    _syncingTimes = true;
    target.jumpTo(offset);
    _syncingTimes = false;
  }

  void _change(VoidCallback update) => setState(update);

  @override
  void dispose() {
    _headerTimes.dispose();
    _bodyTimes.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _headerTimes.addListener(() => _syncTimes(_headerTimes, _bodyTimes));
    _bodyTimes.addListener(() => _syncTimes(_bodyTimes, _headerTimes));
    _consume();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) _consume();
  }

  @override
  void didUpdateWidget(covariant CgyyReservationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _sites = [];
      _site = null;
      _selected.clear();
      _lastDaySnapshot = null;
      _consumed = null;
      _generation++;
      _pending = false;
      _afterRevision = oldWidget.snapshot.readContext?.requestRevision ?? -1;
    }
    if (!oldWidget.query.hasSameParameters(widget.query)) _selected.clear();
    _consume();
  }

  /// 当前表格依据：加载中且新快照尚无日表时沿用上一张。
  FeatureSnapshot get _view {
    final last = _lastDaySnapshot;
    return _busy && _dayOf(widget.snapshot) == null && last != null
        ? last
        : widget.snapshot;
  }

  CgyyDayPresentation? get _day => _dayOf(_view);

  static CgyyDayPresentation? _dayOf(FeatureSnapshot snapshot) {
    final days = snapshot.details
        .map((d) => d.presentation)
        .whereType<CgyyDayPresentation>()
        .toList();
    return days.length == 1 ? days.single : null;
  }

  bool get _busy =>
      _pending || widget.snapshot.status == FeatureLoadStatus.loading;

  void _consume() {
    final snapshot = widget.snapshot;
    if (identical(snapshot, _consumed) ||
        (!const {
              FeatureLoadStatus.success,
              FeatureLoadStatus.stale,
              FeatureLoadStatus.empty,
            }.contains(snapshot.status) &&
            !(snapshot.status == FeatureLoadStatus.loading &&
                snapshot.evidence?.origin == DataOrigin.persisted)))
      return;
    if (_afterRevision != null &&
        (snapshot.readContext?.requestRevision ?? -1) <= _afterRevision!)
      return;
    _afterRevision = null;
    _consumed = snapshot;
    final details = snapshot.details;
    if (details.isNotEmpty &&
        details.every((d) => d.presentation is CgyySitePresentation)) {
      _sites = details
          .map((d) => d.presentation! as CgyySitePresentation)
          .toList();
      if (_campus != '全部' && !_sites.any((s) => s.campusName == _campus))
        _campus = '全部';
      final choices = _visibleSites;
      if (choices.isNotEmpty && snapshot.status == FeatureLoadStatus.success) {
        final previous = choices.where((s) => s.id == _site);
        final next = previous.isEmpty ? choices.first : previous.single;
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _generation ||
              !identical(snapshot, widget.snapshot))
            return;
          if (!TickerMode.valuesOf(context).enabled) {
            _consumed = null;
            return;
          }
          _selectSite(next.id, widget.query.date ?? _parseDay(next.queryDate));
        });
      }
    } else if (_day case final day?) {
      _site = day.venueSiteId;
    }
    final valid = _actions.keys.toSet();
    _selected.removeWhere((key) => !valid.contains(key));
  }

  List<CgyySitePresentation> get _visibleSites => _sites
      .where(
        (s) =>
            s.id > 0 &&
            (_campus == '全部' || s.campusName == _campus) &&
            _sites.where((other) => other.id == s.id).length == 1,
      )
      .toList();

  Future<void> _selectSite(int id, DateTime? date) async {
    if (widget.onQuery == null) return;
    final generation = ++_generation;
    _change(() {
      _site = id;
      _selected.clear();
      _pending = true;
    });
    try {
      await widget.onQuery!(
        FeatureQuery(
          view: FeatureQueryView.cgyyDayInfo,
          siteId: id,
          date: date,
        ),
      );
    } finally {
      if (mounted && generation == _generation) _change(() => _pending = false);
    }
  }

  DateTime? _parseDay(String? value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String().split('T').first != value)
      return null;
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (_dayOf(snapshot) != null) _lastDaySnapshot = snapshot;
    final day = _day;
    if ((_sites.isEmpty || snapshot.evidence?.origin == DataOrigin.persisted) &&
        day == null)
      // 缓存楼层先于网络到达；加载期间显示加载而不是通用列表，离线时才保留只读列表。
      return _busy || snapshot.status == FeatureLoadStatus.loading
          ? const LoadingPlaceholder()
          : widget.fallback;
    if (snapshot.details.any(
      (d) =>
          d.presentation is! CgyySitePresentation &&
          d.presentation is! CgyyDayPresentation &&
          d.presentation is! CgyySlotPresentation,
    ))
      return widget.fallback;
    final actions = _actions;
    return Column(
      children: [
        buildInlineChips(context),
        SizedBox(
          height: 2,
          child: _busy && day != null
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        Expanded(
          child:
              day == null &&
                  (_busy || (_site == null && _visibleSites.isNotEmpty))
              ? const LoadingPlaceholder()
              : snapshot.status == FeatureLoadStatus.failure
              ? widget.fallback
              : day == null
              ? const Center(child: Text('当前暂无研讨室时段'))
              : Padding(
                  padding: UbaaTheme.pageInsets(context, top: 0, bottom: 0),
                  child: _table(context, day),
                ),
        ),
        if (_selected.isNotEmpty) _selectionBar(context, actions),
      ],
    );
  }

  String _selectionLabel(List<CgyyReserveAction> selected) {
    final first = selected.first;
    final sites = _sites.where((s) => s.id == first.venueSiteId);
    final slots = widget.snapshot.details
        .map((d) => d.presentation)
        .whereType<CgyySlotPresentation>()
        .where(
          (p) =>
              p.spaceId == first.spaceId && p.venueSiteId == first.venueSiteId,
        )
        .toList();
    final ranges = [
      for (final action in selected)
        for (final p in slots.where((p) => p.timeId == action.timeId))
          '${p.beginTime ?? ''}–${p.endTime ?? ''}',
    ];
    return [
      if (sites.length == 1) _siteLabel(sites.single),
      if (slots.isNotEmpty) slots.first.spaceName,
      first.reservationDate,
      ranges.join('、'),
    ].join('\n');
  }

  void _toggleSlot(String key, Map<String, CgyyReserveAction> actions) =>
      _change(() {
        if (_selected.contains(key)) {
          _selected.remove(key);
          return;
        }
        uiSelectCgyyAction(_selected, actions, key);
      });

  String _siteLabel(CgyySitePresentation site) {
    final venue = site.venueName.trim();
    final floor = site.siteName.trim();
    final short = venue.replaceFirst(RegExp(r'研讨室$'), '');
    return [
      short.isEmpty ? venue : short,
      if (floor != venue) floor,
    ].where((value) => value.isNotEmpty).toSet().join(' / ');
  }

  String _campusLabel(String name) => name.contains('学院路')
      ? '学院路'
      : name.contains('沙河')
      ? '沙河'
      : name;
  int _campusRank(String name) => name.contains('学院路')
      ? 0
      : name.contains('沙河')
      ? 1
      : 99;
}

/// 时段格子图例，供顶栏弹出说明使用。
class CgyySlotLegend extends StatelessWidget {
  const CgyySlotLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, Color background, Color fg) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, size: 16, color: fg),
              ),
              const SizedBox(width: 10),
              Text(label),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(
          Icons.add,
          '可预约',
          colors.primaryContainer,
          colors.onPrimaryContainer,
        ),
        item(Icons.check, '已选择', colors.primary, colors.onPrimary),
        item(
          Icons.remove,
          '不可预约',
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
        ),
      ],
    );
  }
}
