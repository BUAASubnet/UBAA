import 'package:flutter/material.dart';

/// 筛选面板里的一组选项：小标题加一行可换行的选择标签，各功能的筛选共用。
class UiFilterSection extends StatelessWidget {
  const UiFilterSection({super.key, required this.title, required this.chips});
  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    ),
  );
}
