import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One track with a sliding selection, shared by the years and the icon switch.
class HealthCloudSwitch extends StatefulWidget {
  const HealthCloudSwitch({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.iconsOnly = false,
  });

  final List<(String, Widget)> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool iconsOnly;

  @override
  State<HealthCloudSwitch> createState() => _HealthCloudSwitchState();
}

class _HealthCloudSwitchState extends State<HealthCloudSwitch> {
  int? _dragIndex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final count = widget.items.length;
      final textHeight = MediaQuery.textScalerOf(context).scale(14);
      final height = widget.iconsOnly ? 52.0 : math.max(40.0, textHeight + 20);
      final width = widget.iconsOnly
          ? math.min(constraints.maxWidth, 4 + (height - 4) * count)
          : math.max(constraints.maxWidth, count * (textHeight * 2.6 + 14));
      final scrolls = width > constraints.maxWidth;
      final canDrag = !scrolls && count > 1;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final radius = BorderRadius.circular(widget.iconsOnly ? height / 2 : 12);
      const inset = 3.0;
      final itemWidth = (width - 2 * inset) / count;
      final current = _dragIndex ?? widget.selected;

      void preview(DragUpdateDetails details) {
        final x = rtl
            ? width - details.localPosition.dx
            : details.localPosition.dx;
        final index = ((x - inset) / itemWidth).floor().clamp(0, count - 1);
        if (index != _dragIndex) setState(() => _dragIndex = index);
      }

      final track = SizedBox(
        height: height,
        width: width,
        child: Material(
          color: colors.surfaceContainerHighest,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: canDrag ? preview : null,
            onHorizontalDragCancel: canDrag
                ? () => setState(() => _dragIndex = null)
                : null,
            onHorizontalDragEnd: canDrag
                ? (_) {
                    final index = _dragIndex;
                    setState(() => _dragIndex = null);
                    if (index != null && index != widget.selected) {
                      widget.onSelected(index);
                    }
                  }
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (current >= 0)
                  AnimatedPositionedDirectional(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    start: inset + current * itemWidth,
                    width: itemWidth,
                    top: inset,
                    bottom: inset,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(
                          widget.iconsOnly ? height / 2 : 9,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: .14),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: inset),
                  child: Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Expanded(child: _item(context, i, radius)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return scrolls
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: track,
            )
          : track;
    },
  );

  Widget _item(BuildContext context, int index, BorderRadius radius) {
    final (label, content) = widget.items[index];
    final selected = index == widget.selected;
    final colors = Theme.of(context).colorScheme;
    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: () => widget.onSelected(index),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: radius,
        onTap: () => widget.onSelected(index),
        child: Center(
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: content,
          ),
        ),
      ),
    );
    return widget.iconsOnly
        ? Tooltip(message: label, excludeFromSemantics: true, child: item)
        : item;
  }
}
