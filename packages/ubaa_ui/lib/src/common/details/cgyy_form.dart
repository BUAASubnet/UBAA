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
    );
    if (input != null && mounted && identical(original, widget.details))
      await widget.onCgyySubmitWrite?.call(input);
  }
}
