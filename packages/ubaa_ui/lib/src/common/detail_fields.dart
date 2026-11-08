import 'package:flutter/material.dart';

/// 详情里的“字段名 · 值”一行：字段名固定宽度、次要色，值可换行，多行之间左缘对齐。
class DetailField extends StatelessWidget {
  const DetailField({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;

  /// 需要强调时（如临近截止）覆盖值的样式。
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: valueStyle ?? theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
