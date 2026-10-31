import 'package:flutter/material.dart';

/// 窄屏分页只启用当前页的动画，已访问页面保留状态。
class TabPager extends StatelessWidget {
  const TabPager({
    super.key,
    required this.controller,
    required this.selectedIndex,
    required this.enabled,
    required this.itemCount,
    required this.onSelected,
    required this.itemBuilder,
  });
  final PageController controller;
  final int selectedIndex, itemCount;
  final bool enabled;
  final ValueChanged<int> onSelected;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: controller,
    physics: enabled ? null : const NeverScrollableScrollPhysics(),
    itemCount: itemCount,
    onPageChanged: (index) {
      if (index != selectedIndex) onSelected(index);
    },
    itemBuilder: (context, index) => _KeepAlivePage(
      key: ValueKey(index),
      child: TickerMode(
        enabled: index == selectedIndex,
        child: itemBuilder(context, index),
      ),
    ),
  );
}

/// 底栏顶部留白 8pt，底部安全区最多保留 20pt，仍避开 Home 指示条。
class CompactNavigationBar extends StatelessWidget {
  const CompactNavigationBar({super.key, required this.child});

  static const double _topGap = 8;
  static const double _maxBottomInset = 20;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color:
          theme.navigationBarTheme.backgroundColor ??
          theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(top: _topGap),
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: media.padding.bottom > _maxBottomInset
                  ? _maxBottomInset
                  : media.padding.bottom,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 滑出屏幕的分页保留状态，避免首页与“我的”每次滑回都重建。
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
