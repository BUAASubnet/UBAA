import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// 账号或路线退出当前作用域时，关闭该作用域打开的编辑器和弹窗。
class UiScopeBoundary extends StatefulWidget {
  const UiScopeBoundary({
    super.key,
    required this.generation,
    required this.child,
  });
  final ValueListenable<int> generation;
  final Widget child;
  @override
  State<UiScopeBoundary> createState() => _UiScopeBoundaryState();
}

class _UiScopeBoundaryState extends State<UiScopeBoundary> {
  @override
  void initState() {
    super.initState();
    widget.generation.addListener(changed);
  }

  ModalRoute<dynamic>? route;
  NavigatorState? navigator;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    navigator = Navigator.of(context);
  }

  void changed() {
    final owner = navigator;
    final opened = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (owner?.mounted == true && opened?.isActive == true)
        owner!.removeRoute(opened!);
    });
  }

  @override
  void dispose() {
    widget.generation.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
