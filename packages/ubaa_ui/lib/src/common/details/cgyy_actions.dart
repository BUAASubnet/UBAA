part of 'detail_list.dart';

extension CgyyDetailActions on _FeatureDetailListState {
  List<Widget> _cgyyCancelWriteFields(CgyyCancelAction? cgyyCancelAction) =>
      <Widget>[
        if (cgyyCancelAction != null &&
            widget.onCgyyCancelWrite != null) ...<Widget>[
          const SizedBox(height: 12),
          _cgyyCancelButton(cgyyCancelAction),
        ],
      ];

  Widget _cgyyCancelButton(CgyyCancelAction action) => TextButton(
    onPressed: !widget.writesEnabled
        ? null
        : () => widget.onCgyyCancelWrite!(action),
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    child: const Text('取消预约'),
  );

  List<Widget> _cgyyReserveWriteFields(
    BuildContext context,
    CgyyReserveAction? cgyyReservation,
  ) => <Widget>[
    if (cgyyReservation != null &&
        widget.onCgyySubmitWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: !widget.writesEnabled
            ? null
            : () => _showCgyyReservationForm(
                context,
                cgyyReservation,
                _cgyyReserveCandidates(cgyyReservation),
              ),
        icon: const Icon(Icons.event_available),
        label: const Text('准备研讨室预约'),
      ),
    ],
  ];

  CgyyCancelAction? _cgyyCancelAction(FeatureDetail detail) {
    if (widget.feature != FeatureId.cgyy) return null;
    final action = detail.action<CgyyCancelAction>();
    return action?.hasCanonicalTarget == true ? action : null;
  }

  CgyyReserveAction? _cgyyReserveAction(FeatureDetail detail) {
    if (widget.feature != FeatureId.cgyy) return null;
    final action = detail.action<CgyyReserveAction>();
    return action != null && _isUsableCgyyReserveAction(action) ? action : null;
  }

  bool _isUsableCgyyReserveAction(CgyyReserveAction action) =>
      action.eligibility == ActionEligibility.allowed &&
      action.venueSiteId > 0 &&
      action.reservationDate.trim().isNotEmpty &&
      action.spaceId > 0 &&
      action.timeId > 0 &&
      action.timeOrdinal >= 0 &&
      (action.venueSpaceGroupId == null || action.venueSpaceGroupId! > 0);

  List<CgyyReserveAction> _cgyyReserveCandidates(CgyyReserveAction target) {
    final seen = <String>{};
    final candidates = <CgyyReserveAction>[];
    for (final detail in widget.details) {
      final candidate = _cgyyReserveAction(detail);
      if (candidate == null ||
          candidate.venueSiteId != target.venueSiteId ||
          candidate.reservationDate.trim() != target.reservationDate.trim() ||
          candidate.spaceId != target.spaceId ||
          candidate.venueSpaceGroupId != target.venueSpaceGroupId) {
        continue;
      }
      if (seen.add(uiCgyyActionKey(candidate))) candidates.add(candidate);
    }
    candidates.sort(
      (left, right) => left.timeOrdinal.compareTo(right.timeOrdinal),
    );
    return List<CgyyReserveAction>.unmodifiable(candidates);
  }
}
