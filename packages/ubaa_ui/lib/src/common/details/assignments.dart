part of 'detail_list.dart';

extension AssignmentsDetailActions on _FeatureDetailListState {
  List<Widget> _signinWriteFields(
    BuildContext context,
    SigninPerformAction? signinAction,
    bool canSignin, {
    String deniedMessage = '该课程已签到，不能重复提交。',
  }) => <Widget>[
    if (widget.feature == FeatureId.signin &&
        widget.onSigninWrite != null &&
        signinAction != null) ...<Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: !widget.writesEnabled
            ? null
            : canSignin
            ? () => widget.onSigninWrite!(signinAction)
            : null,
        icon: const Icon(Icons.how_to_reg),
        label: const Text('签到'),
      ),
      // 资格无法确认时只禁用按钮，不向用户解释内部状态。
      if (!canSignin && signinAction.eligibility == ActionEligibility.denied)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            deniedMessage,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];
}
