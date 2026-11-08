import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

Widget uiRailIdentity(
  BuildContext context,
  bool extended, {
  required UserSummary? user,
  required VoidCallback onTap,
  bool selected = false,
}) {
  final theme = Theme.of(context);
  const iconWidget = UiAppIcon(size: 36);

  final name = user?.preferredName ?? '用户';
  final username = user?.username ?? '';

  // 打开“我的”时与导航项同样高亮，表明当前所在页面。
  return Material(
    color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        // 与侧栏导航图标同一左边线。
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: extended
            ? Row(
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
    ),
  );
}

/// 应用图标；侧栏身份与关于页共用同一圆角比例。
class UiAppIcon extends StatelessWidget {
  const UiAppIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      'assets/icons/app_icon.png',
      package: 'ubaa_ui',
      width: size,
      height: size,
      // 按显示尺寸解码 1024 像素原图，首次出现不再延迟。
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.school_outlined,
            size: size * 0.6,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    ),
  );
}
