part of 'reservation_flow.dart';

extension CgyyReservationChoices on CgyyReservationFlowState {
  Widget buildInlineChips(BuildContext context) {
    final campuses = _sites.map((s) => s.campusName).toSet().toList()
      ..sort((a, b) => _campusRank(a).compareTo(_campusRank(b)));
    final day = _day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_sites.isNotEmpty)
          _ChoiceStrip(
            key: const ValueKey('cgyy-campuses'),
            children: [
              for (final campus in ['全部', ...campuses])
                FilterChip(
                  key: ValueKey('cgyy-campus-${_campusLabel(campus)}'),
                  label: Text(_campusLabel(campus)),
                  selected: _campus == campus,
                  onSelected: _busy || widget.onQuery == null
                      ? null
                      : (_) {
                          _change(() {
                            _campus = campus;
                            _selected.clear();
                          });
                          final sites = _visibleSites;
                          if (sites.isNotEmpty) {
                            final previous = sites.where((s) => s.id == _site);
                            unawaited(
                              _selectSite(
                                (previous.isEmpty
                                        ? sites.first
                                        : previous.single)
                                    .id,
                                _parseDay(day?.reservationDate) ??
                                    widget.query.date,
                              ),
                            );
                          }
                        },
                ),
            ],
          ),
        if (day != null && day.availableDates.isNotEmpty)
          _ChoiceStrip(
            key: const ValueKey('cgyy-dates'),
            children: [
              for (final date in day.availableDates.toSet())
                if (_parseDay(date) != null)
                  FilterChip(
                    key: ValueKey('cgyy-date-$date'),
                    tooltip: date,
                    label: Text(_dateLabel(date)),
                    selected: day.reservationDate == date,
                    onSelected: _busy || widget.onQuery == null
                        ? null
                        : (_) => unawaited(
                            _selectSite(day.venueSiteId, _parseDay(date)),
                          ),
                  ),
            ],
          ),
        if (_visibleSites.isNotEmpty)
          _ChoiceStrip(
            key: const ValueKey('cgyy-sites'),
            children: [
              for (final site in _visibleSites)
                FilterChip(
                  key: ValueKey('cgyy-site-${site.id}'),
                  label: Text(_siteLabel(site)),
                  selected: _site == site.id,
                  onSelected: _busy || widget.onQuery == null
                      ? null
                      : (_) => unawaited(
                          _selectSite(
                            site.id,
                            _parseDay(day?.reservationDate) ??
                                widget.query.date,
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }

  String _dateLabel(String value) {
    final date = _parseDay(value);
    if (date == null) return value;
    final now = homeCampusTime(clock.now());
    final today =
        date.year == now.year && date.month == now.month && date.day == now.day;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final prefix = date.year == now.year ? '' : '${date.year}年';
    return '$prefix${date.month}月${date.day}日 ${today ? '今天' : weekdays[date.weekday - 1]}';
  }
}

/// 保留旧版横向直选，滚动条提示还有选项并支持鼠标拖动。
class _ChoiceStrip extends StatefulWidget {
  const _ChoiceStrip({super.key, required this.children});
  final List<Widget> children;

  @override
  State<_ChoiceStrip> createState() => _ChoiceStripState();
}

class _ChoiceStripState extends State<_ChoiceStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: UbaaTheme.pageInsets(context, top: 2, bottom: 2),
    child: Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            for (final child in widget.children)
              Padding(padding: const EdgeInsets.only(right: 6), child: child),
          ],
        ),
      ),
    ),
  );
}
