import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../shared/text.dart' show uiNonBlank;

/// 我的资料：头部显示姓名与学号，下方直接列出资料。
/// 手机和邮箱上游已打码，原样显示。
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({required this.user});
  final UserSummary? user;

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = uiNonBlank(user?.preferredName) ?? '未登录';
    final studentId = uiNonBlank(user?.schoolId) ?? uiNonBlank(user?.username);
    final rows = <Widget>[
      if (user != null) ...[
        if (uiNonBlank(user.username) case final login? when login != studentId)
          _ProfileRow(label: '用户名', value: login),
        if (uiNonBlank(user.department) case final department?)
          _ProfileRow(label: '院系', value: department),
        if (uiNonBlank(user.phone) case final phone?)
          _ProfileRow(label: '手机号', value: phone),
        if (uiNonBlank(user.email) case final email?)
          _ProfileRow(label: '邮箱', value: email),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    package: 'ubaa_ui',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => CircleAvatar(
                      radius: 28,
                      child: Text(name.characters.first),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      if (studentId != null && studentId != name)
                        Text(
                          studentId,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (user?.profileNotice case final notice?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              notice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    row,
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
