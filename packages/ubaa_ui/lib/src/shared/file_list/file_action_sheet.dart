import 'package:flutter/material.dart';

import '../dialogs/sheet.dart';

class UiFileAction<T> {
  const UiFileAction({
    required this.value,
    required this.label,
    required this.icon,
    this.quick = false,
    this.danger = false,
    this.key,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool quick, danger;
  final Key? key;
}

/// 文件操作面板。快捷操作在上方，普通操作和危险操作分列。
Future<T?> showUiFileActions<T>(
  BuildContext context, {
  required String name,
  required List<UiFileAction<T>> actions,
  String? meta,
  bool Function(T)? enabled,
  Widget Function(Widget)? boundary,
}) => showUiSheet<T>(
  context,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quick = actions.where((action) => action.quick && !action.danger);
    final rest = actions.where((action) => !action.quick && !action.danger);
    final danger = actions.where((action) => action.danger);
    Widget quickButton(UiFileAction<T> a) {
      final on = enabled?.call(a.value) ?? true;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: on ? () => Navigator.pop(context, a.value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(
                      alpha: on ? .7 : .3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    a.icon,
                    color: on
                        ? colors.onSecondaryContainer
                        : colors.onSurface.withValues(alpha: .38),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  a.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: on ? null : colors.onSurface.withValues(alpha: .38),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget tile(UiFileAction<T> a) => ListTile(
      key: a.key,
      contentPadding: EdgeInsets.zero,
      enabled: enabled?.call(a.value) ?? true,
      leading: Icon(a.icon, color: a.danger ? colors.error : null),
      title: Text(
        a.label,
        style: a.danger ? TextStyle(color: colors.error) : null,
      ),
      onTap: () => Navigator.pop(context, a.value),
    );
    final sheet = UiSheetBody(
      title: name,
      subtitle: meta,
      children: [
        if (quick.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [for (final a in quick) quickButton(a)]),
          ),
        if (rest.isNotEmpty) ...[
          const Divider(height: 1),
          for (final a in rest) tile(a),
        ],
        if (danger.isNotEmpty) ...[
          const Divider(height: 1),
          for (final a in danger) tile(a),
        ],
      ],
    );
    return boundary == null ? sheet : boundary(sheet);
  },
);
