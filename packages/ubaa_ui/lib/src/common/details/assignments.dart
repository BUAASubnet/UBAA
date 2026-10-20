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
        label: const Text('准备签到'),
      ),
      if (!canSignin)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            signinAction.eligibility == ActionEligibility.denied
                ? deniedMessage
                : '当前签到资格无法确认，请刷新后重试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  ];
}
