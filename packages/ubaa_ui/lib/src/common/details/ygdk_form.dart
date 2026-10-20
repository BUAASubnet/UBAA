part of 'detail_list.dart';

extension YgdkWriteForm on _FeatureDetailListState {
  Future<void> _showYgdkForm(
    BuildContext context, {
    required YgdkSubmitAction action,
    required String title,
  }) async {
    final original = widget.details;
    final input = await uiCollectYgdkForm(
      context,
      items: [
        FeatureDetail(title: title, actions: [action]),
      ],
      initialAction: action,
      onPickPhoto: widget.onPickYgdkPhoto,
      onCapturePhoto: widget.onCaptureYgdkPhoto,
      formContext: widget.ygdkFormContext,
    );
    if (input != null &&
        mounted &&
        widget.writesEnabled &&
        identical(original, widget.details)) {
      await widget.onYgdkSubmitWrite?.call(input);
    }
  }
}
