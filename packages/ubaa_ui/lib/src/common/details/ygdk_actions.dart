part of 'detail_list.dart';

extension YgdkDetailActions on _FeatureDetailListState {
  List<Widget> _ygdkWriteFields(
    BuildContext context,
    YgdkSubmitAction? ygdkAction,
    FeatureDetail detail,
  ) => <Widget>[
    if (ygdkAction != null && widget.onYgdkSubmitWrite != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () =>
            _showYgdkForm(context, action: ygdkAction, title: detail.title),
        icon: const Icon(Icons.directions_run),
        label: const Text('准备阳光打卡'),
      ),
    ],
  ];

  YgdkSubmitAction? _ygdkAction(FeatureDetail detail) {
    if (widget.feature != FeatureId.ygdk) return null;
    final action = detail.action<YgdkSubmitAction>();
    return action?.hasCanonicalTarget == true ? action : null;
  }
}
