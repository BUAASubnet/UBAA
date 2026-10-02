part of '../../widgets.dart';

/// 让Scaffold为底部操作保留位置，已有Snackbar不会遮挡继续/取消。
class _FormActionBar extends StatelessWidget {
  const _FormActionBar({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: child,
      ),
    ),
  );
}
