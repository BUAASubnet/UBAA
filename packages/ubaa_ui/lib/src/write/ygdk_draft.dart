part of '../widgets.dart';

/// 草稿仅属于当前读取代次；照片由表单持有，关闭即释放。
class _YgdkFormDraft extends ChangeNotifier {
  String start = '', end = '', place = '操场';
  String? itemKey;
  bool share = false;
  int generation = 0;

  void clear() {
    start = end = '';
    place = '操场';
    itemKey = null;
    share = false;
    generation++;
    notifyListeners();
  }
}

class _YgdkFormContext {
  const _YgdkFormContext({
    required this.draft,
    this.route,
    this.onRouteOptions,
  });
  final _YgdkFormDraft draft;
  final ConnectionMode? route;
  final Future<void> Function(Map<String, ConnectionMode>)? onRouteOptions;
}

String _ygdkItemKey(YgdkSubmitAction action) =>
    '${action.classifyId}:${action.itemId}';

Future<YgdkSubmitInput?> _collectYgdkForm(
  BuildContext context, {
  required List<FeatureDetail> items,
  required YgdkPhotoPicker? onPickPhoto,
  _YgdkFormContext? formContext,
  YgdkSubmitAction? initialAction,
}) async {
  final data = formContext ?? _YgdkFormContext(draft: _YgdkFormDraft());
  final generation = data.draft.generation;
  final input = await Navigator.of(context).push<YgdkSubmitInput>(
    MaterialPageRoute(
      builder: (_) => _YgdkFormPage(
        items: items,
        onPickPhoto: onPickPhoto,
        data: data,
        initialAction: initialAction,
      ),
    ),
  );
  final valid = generation == data.draft.generation;
  if (formContext == null) data.draft.dispose();
  return valid ? input : null;
}
