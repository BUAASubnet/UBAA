part of 'form.dart';

Future<YgdkSubmitInput?> uiCollectYgdkForm(
  BuildContext context, {
  required List<FeatureDetail> items,
  required YgdkPhotoPicker? onPickPhoto,
  YgdkPhotoPicker? onCapturePhoto,
  YgdkFormContext? formContext,
  YgdkSubmitAction? initialAction,
}) async {
  final data = formContext ?? YgdkFormContext(draft: YgdkFormDraft());
  final generation = data.draft.generation;
  final input = await Navigator.of(context).push<YgdkSubmitInput>(
    MaterialPageRoute(
      builder: (_) => _YgdkFormPage(
        items: items,
        onPickPhoto: onPickPhoto,
        onCapturePhoto: onCapturePhoto,
        data: data,
        initialAction: initialAction,
      ),
    ),
  );
  final valid = generation == data.draft.generation;
  if (formContext == null) data.draft.dispose();
  return valid ? input : null;
}
