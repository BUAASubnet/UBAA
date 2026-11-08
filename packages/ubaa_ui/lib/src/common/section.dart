import 'package:flutter/material.dart';

/// 页面内分区标题；页面顶层标题用 headlineSmall 粗体，卡片标题用 titleMedium。
class UiSectionTitle extends StatelessWidget {
  const UiSectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

/// 每行只有一个导航动作，长标题和说明可自然换行。
class UiEntryCard extends StatelessWidget {
  const UiEntryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        // 紧凑内边距：手机单列时学习页八个入口无需滚动即可看全。
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 宽度允许时把同类卡片排成多列；同一行等高，窄屏退回单列。
class UiAdaptiveGrid extends StatelessWidget {
  const UiAdaptiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 320,
    this.maxColumns = 3,
    this.spacing = 12,
  });
  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth = MediaQuery.textScalerOf(context).scale(minItemWidth);
      final columns = ((constraints.maxWidth + spacing) / (minWidth + spacing))
          .floor()
          .clamp(1, maxColumns);
      final rows = <Widget>[
        for (var start = 0; start < children.length; start += columns)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) SizedBox(width: spacing),
                  Expanded(
                    child: i < children.length
                        ? children[i]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) SizedBox(height: spacing),
            row,
          ],
        ],
      );
    },
  );
}
