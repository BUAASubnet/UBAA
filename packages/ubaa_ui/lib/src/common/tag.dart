import 'package:flutter/material.dart';

/// 标签色调：中性说明、强调状态、需要留意、错误限制；另可按来源颜色淡染。
enum UiTagTone { neutral, primary, warning, error }

/// 全应用统一的小标签：8 圆角、labelMedium，可带前置图标。
///
/// 传入 [color] 时按该颜色淡染（来源色、作业状态色），否则使用 [tone]。
class UiTag extends StatelessWidget {
  const UiTag(
    this.label, {
    super.key,
    this.tone = UiTagTone.neutral,
    this.icon,
    this.color,
  });
  final String label;
  final UiTagTone tone;
  final IconData? icon;
  final Color? color;

  /// 标签的前景与背景色，供需要自绘点击区域的标签复用。
  static (Color, Color) colorsOf(
    BuildContext context, {
    UiTagTone tone = UiTagTone.neutral,
    Color? color,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (color != null) return (color, color.withValues(alpha: .12));
    return switch (tone) {
      UiTagTone.neutral => (
        colors.onSurfaceVariant,
        colors.surfaceContainerHighest,
      ),
      UiTagTone.primary => (colors.onPrimaryContainer, colors.primaryContainer),
      UiTagTone.warning => (
        colors.onTertiaryContainer,
        colors.tertiaryContainer,
      ),
      UiTagTone.error => (colors.onErrorContainer, colors.errorContainer),
    };
  }

  static const radius = 8.0;
  static const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsOf(context, tone: tone, color: color);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
    );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
                Flexible(child: text),
              ],
            ),
    );
  }
}
