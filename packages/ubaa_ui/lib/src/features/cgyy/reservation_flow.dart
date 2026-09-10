part of '../../widgets.dart';

class _CgyyReservationFlow extends StatefulWidget {
  const _CgyyReservationFlow({
    required this.snapshot,
    required this.query,
    required this.cacheEpoch,
    required this.filter,
    required this.fallback,
    required this.onQuery,
    this.onSubmit,
    required this.formContext,
    required this.onChoicesChanged,
    super.key,
    required this.onRetry,
  });
  final FeatureSnapshot snapshot;
  final FeatureQuery query;
  final int cacheEpoch;
  final String filter;
  final Widget fallback;
  final Future<void> Function(FeatureQuery)? onQuery;
  final CgyyReservationStarter? onSubmit;
  final _CgyyFormContext formContext;
  final VoidCallback onChoicesChanged;
  final Future<void> Function() onRetry;
  @override
  State<_CgyyReservationFlow> createState() => _CgyyReservationFlowState();
}

class _CgyyReservationFlowState extends State<_CgyyReservationFlow> {
  List<CgyySitePresentation> _sites = [];
  String _campus = '全部';
  int? _site;
  final _selected = <String>{};
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

  void _publishChoices() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onChoicesChanged();
  });

  void _change(VoidCallback update) {
    setState(update);
    _publishChoices();
  }

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
    _publishChoices();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) _consume();
  }

  @override
  void didUpdateWidget(covariant _CgyyReservationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _sites = [];
      _site = null;
      _selected.clear();
      _consumed = null;
      _generation++;
      _pending = false;
      _afterRevision = oldWidget.snapshot.readContext?.requestRevision ?? -1;
    }
    if (!oldWidget.query.hasSameParameters(widget.query)) _selected.clear();
    _consume();
    _publishChoices();
  }

  CgyyDayPresentation? get _day {
    final days = widget.snapshot.details
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
        !const {
          FeatureLoadStatus.success,
          FeatureLoadStatus.stale,
          FeatureLoadStatus.empty,
        }.contains(snapshot.status))
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
    final day = _day;
    if (_sites.isEmpty && day == null) return widget.fallback;
    if (snapshot.details.any(
      (d) =>
          d.presentation is! CgyySitePresentation &&
          d.presentation is! CgyyDayPresentation &&
          d.presentation is! CgyySlotPresentation,
    ))
      return widget.fallback;
    final actions = _actions;
    final selectedSites = _sites
        .where((site) => site.id == day?.venueSiteId)
        .toList();
    return Column(
      children: [
        if (day != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedSites.length == 1)
                    Text(
                      _siteLabel(selectedSites.single),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    day.reservationDate,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : snapshot.status == FeatureLoadStatus.failure
              ? widget.fallback
              : day == null
              ? const Center(child: Text('当前暂无研讨室时段'))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _table(context, day),
                ),
        ),
        if (_selected.isNotEmpty && !_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: widget.onSubmit == null
                  ? null
                  : () async {
                      final selected =
                          _selected.map((key) => actions[key]!).toList()..sort(
                            (a, b) => a.timeOrdinal.compareTo(b.timeOrdinal),
                          );
                      final original = widget.snapshot;
                      final input = await _collectCgyyReservation(
                        context,
                        selected.first,
                        selected,
                        formContext: widget.formContext,
                        initialSelection: selected,
                        selectionLabel: _selectionLabel(selected),
                      );
                      if (mounted &&
                          input != null &&
                          identical(original, widget.snapshot))
                        await widget.onSubmit!(input);
                    },
              child: const Text('下一步'),
            ),
          ),
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
        _selectCgyyAction(_selected, actions, key);
      });

  String _siteLabel(CgyySitePresentation site) =>
      [site.venueName, site.siteName].where((s) => s.isNotEmpty).join(' / ');
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
