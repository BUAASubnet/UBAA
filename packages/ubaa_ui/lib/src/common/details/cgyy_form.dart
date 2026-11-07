part of 'detail_list.dart';

extension CgyyWriteForm on _FeatureDetailListState {
  Future<void> _showCgyyReservationForm(
    BuildContext context,
    CgyyReserveAction target,
    List<CgyyReserveAction> availableActions,
  ) async {
    final original = widget.details;
    final input = await uiCollectCgyyReservation(
      context,
      target,
      availableActions,
      formContext: widget.cgyyFormContext,
      actionLabels: {
        for (final detail in widget.details)
          if (detail.action<CgyyReserveAction>() case final action?)
            uiCgyyActionKey(action): detail.title,
      },
    );
    if (input != null &&
        mounted &&
        widget.writesEnabled &&
        identical(original, widget.details))
      await widget.onCgyySubmitWrite?.call(input);
  }
}
