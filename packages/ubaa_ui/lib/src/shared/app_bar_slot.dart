import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart' show FeatureId;

/// 页面放到顶栏右上角的低频控件（例如校区切换）。
/// 按功能分别登记，外壳只显示当前打开功能的控件。
class UiAppBarSlot extends InheritedWidget {
  const UiAppBarSlot({required this.slot, required super.child});
  final ValueNotifier<Map<FeatureId, Widget>> slot;

  static ValueNotifier<Map<FeatureId, Widget>>? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UiAppBarSlot>()?.slot;

  /// 在帧结束后登记或清除；[action] 为 null 时只清除本功能的控件。
  static void publish(BuildContext context, FeatureId feature, Widget? action) {
    final slot = _of(context);
    if (slot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = {...slot.value};
      if (action != null) {
        next[feature] = action;
      } else if (next.remove(feature) == null) {
        return;
      }
      slot.value = next;
    });
  }

  @override
  bool updateShouldNotify(UiAppBarSlot oldWidget) => slot != oldWidget.slot;
}

/// 顶栏里的紧凑选择：显示当前项，点开列出全部选项。
class UiAppBarPicker<T> extends StatelessWidget {
  const UiAppBarPicker({
    super.key,
    required this.tooltip,
    required this.value,
    required this.options,
    this.onSelected,
  });
  final String tooltip;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.$1 == value).firstOrNull;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: onSelected != null && options.isNotEmpty,
      initialValue: value,
      onSelected: (v) {
        if (v != value) onSelected?.call(v);
      },
      itemBuilder: (_) => [
        for (final option in options)
          CheckedPopupMenuItem<T>(
            value: option.$1,
            checked: option.$1 == value,
            child: Text(option.$2),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 18),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                current?.$2 ?? tooltip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}
