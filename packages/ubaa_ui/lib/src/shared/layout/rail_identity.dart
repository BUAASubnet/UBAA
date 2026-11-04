import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

Widget uiRailIdentity(
  BuildContext context,
  bool extended, {
  required UserSummary? user,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);
  final iconWidget = ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.asset(
      'assets/icons/app_icon.png',
      package: 'ubaa_ui',
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => CircleAvatar(
        radius: 18,
        child: Text((user?.preferredName ?? 'U').characters.first),
      ),
    ),
  );

  final name = user?.preferredName ?? '用户';
  final username = user?.username ?? '';

  return InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: extended
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (username.isNotEmpty && username != name) ...[
                        const SizedBox(height: 2),
                        Text(
                          username,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            )
          : iconWidget,
    ),
  );
}
