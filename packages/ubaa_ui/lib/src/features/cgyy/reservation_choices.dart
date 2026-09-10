part of '../../widgets.dart';

extension _CgyyReservationChoices on _CgyyReservationFlowState {
  Widget buildChoices(BuildContext context) {
    final campuses = _sites.map((s) => s.campusName).toSet().toList()
      ..sort((a, b) => _campusRank(a).compareTo(_campusRank(b)));
    final day = _day;
    return Column(
      children: [
        if (_sites.isNotEmpty)
          _choice<String>(
            '校区',
            _campus,
            {
              for (final campus in ['全部', ...campuses])
                campus: _campusLabel(campus),
            },
            (campus) {
              _change(() {
                _campus = campus;
                _selected.clear();
              });
              final sites = _visibleSites;
              if (sites.isNotEmpty) {
                final previous = sites.where((s) => s.id == _site);
                unawaited(
                  _selectSite(
                    (previous.isEmpty ? sites.first : previous.single).id,
                    _parseDay(day?.reservationDate) ?? widget.query.date,
                  ),
                );
              }
            },
          ),
        if (day != null && day.availableDates.isNotEmpty)
          _choice<String>(
            '预约日期',
            day.reservationDate,
            {
              for (final date in day.availableDates.toSet())
                if (_parseDay(date) != null) date: date,
            },
            (date) => unawaited(_selectSite(day.venueSiteId, _parseDay(date))),
          ),
        if (_sites.isNotEmpty)
          _choice<int>(
            '楼栋 / 楼层',
            _site,
            {for (final site in _visibleSites) site.id: _siteLabel(site)},
            (site) => unawaited(
              _selectSite(
                site,
                _parseDay(day?.reservationDate) ?? widget.query.date,
              ),
            ),
          ),
      ],
    );
  }

  Widget _choice<T>(
    String label,
    T? selected,
    Map<T, String> choices,
    ValueChanged<T> select,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: ValueKey('cgyy-choice-$label'),
          value: choices.containsKey(selected) ? selected : null,
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          selectedItemBuilder: (context) => [
            for (final text in choices.values)
              Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          items: [
            for (final entry in choices.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(entry.value),
                ),
              ),
          ],
          onChanged: _busy || widget.onQuery == null
              ? null
              : (value) {
                  if (value != null) select(value);
                },
        ),
      ),
    ),
  );
}
