import 'package:flutter/material.dart';

/// 随正文自然增高的分区标题。
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
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
                      const SizedBox(height: 4),
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
