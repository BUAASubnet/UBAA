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

/// 概览页（首页等）的大分节标题：标题、可选说明与右侧动作。
///
/// 比页面标题小一级，比卡片标题大一级；多栏并排时各栏高度一致，首张卡片顶端对齐。
class UiSectionHeader extends StatelessWidget {
  const UiSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTitleTap,
    this.titleTooltip,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTitleTap;
  final String? titleTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading = Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    if (onTitleTap case final onTap?) {
      heading = Tooltip(
        message: titleTooltip ?? title,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              heading,
              Icon(
                Icons.chevron_right,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            // 有无右侧按钮时标题行等高。
            constraints: const BoxConstraints(minHeight: 36),
            // 放得下时标题在左、按钮在右；大字号下放不下时按钮换到下一行，
            // 而不是挤压标题或溢出。
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [heading, ?trailing],
            ),
          ),
          if (subtitle case final subtitle?)
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
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
    final grouped = _UiEntryGrouped.of(context);
    final tile = InkWell(
      onTap: onTap,
      // 紧凑内边距：手机单列时学习页八个入口无需滚动即可看全。
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: grouped ? 12 : 10,
        ),
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
    );
    // 分组列表里由外层统一画边框，行内的 Card 去掉边框与底色，只保留点按区域。
    return grouped
        ? Card(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(),
            child: tile,
          )
        : Card(child: tile);
  }
}

class _UiEntryGrouped extends InheritedWidget {
  const _UiEntryGrouped({required super.child});
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_UiEntryGrouped>() != null;
  @override
  bool updateShouldNotify(_UiEntryGrouped oldWidget) => false;
}

/// 入口列表：窄屏单列时合成一张分组卡片，行间以分隔线隔开，减少重复边框与滚动；
/// 宽屏多列时退回独立卡片网格。子项通常是 [UiEntryCard]。
class UiEntryList extends StatelessWidget {
  const UiEntryList({
    super.key,
    required this.children,
    this.minItemWidth = 400,
    this.maxColumns = 2,
  });
  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth = MediaQuery.textScalerOf(context).scale(minItemWidth);
      if (maxColumns > 1 && constraints.maxWidth >= minWidth * 2 + 12) {
        return UiAdaptiveGrid(
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
          children: children,
        );
      }
      final card = Theme.of(context).cardTheme;
      return Material(
        color: card.color,
        shape: card.shape,
        clipBehavior: Clip.antiAlias,
        child: _UiEntryGrouped(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                // 分隔线从图标右侧开始，与文字左缘对齐。
                if (i > 0) const Divider(height: 1, indent: 72),
                child,
              ],
            ],
          ),
        ),
      );
    },
  );
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
