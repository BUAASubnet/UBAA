part of 'detail_list.dart';

extension LibbookDetailActions on _FeatureDetailListState {
  List<Widget> _libbookCancelWriteFields(
    BuildContext context,
    LibbookCancelAction? libbookCancelAction,
    bool canLibbookCancel,
  ) => <Widget>[
    if (libbookCancelAction != null &&
        widget.onLibbookCancelWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: !widget.writesEnabled
            ? null
            : canLibbookCancel
            ? () => widget.onLibbookCancelWrite!(libbookCancelAction)
            : null,
        icon: const Icon(Icons.event_busy),
        label: const Text('取消预约'),
      ),
      if (!canLibbookCancel &&
          libbookCancelAction.eligibility == ActionEligibility.denied)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '该预约当前不可取消。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];

  List<Widget> _libbookReserveWriteFields(
    BuildContext context,
    LibbookReserveAction? libbookReserveAction,
    bool canLibbookReserve,
  ) => <Widget>[
    if (libbookReserveAction != null &&
        widget.onLibbookReserveWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: !widget.writesEnabled
            ? null
            : canLibbookReserve
            ? () => widget.onLibbookReserveWrite!(libbookReserveAction)
            : null,
        icon: const Icon(Icons.event_available),
        label: const Text('预约此座位'),
      ),
      if (!canLibbookReserve &&
          libbookReserveAction.eligibility == ActionEligibility.denied)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '该座位当前不可预约。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];
}
