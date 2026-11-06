import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/tag.dart';
import '../../shared/feature_icons.dart' show uiFeatureIcon;
import '../../theme.dart';

/// 首页待办和加载提示使用的来源短名。
String uiHomeFeatureLabel(FeatureId feature) => switch (feature) {
  FeatureId.exam => '考试',
  FeatureId.bykc => '博雅',
  FeatureId.spoc => 'SPOC',
  FeatureId.judge => '希冀',
  FeatureId.cgyy => '研讨室',
  FeatureId.signin => '签到',
  FeatureId.ygdk => '阳光打卡',
  _ => feature.title,
};

/// 首页待办卡片：来源标签与课程等补充信息同处一行，标题单独占行。
class HomeTodoCard extends StatelessWidget {
  const HomeTodoCard({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
    this.onSignin,
    this.onRefreshSignin,
    this.signing = false,
    this.signinUncertain = false,
  });
  final HomeTodo item;
  final DateTime now;
  final VoidCallback onTap;
  final Future<void> Function()? onSignin, onRefreshSignin;
  final bool signing, signinUncertain;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.feature == FeatureId.signin && signing
        ? '签到处理中'
        : signinUncertain
        ? '结果待确认'
        : item.statusLabel;
    final subtitle = item.subtitle.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.feature == FeatureId.signin
            ? (signing ? null : onSignin ?? onRefreshSignin)
            : item.navigation == null
            ? null
            : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 元信息行：来源、课程或地点、非“待××”状态；标题单独占行。
                        Row(
                          children: [
                            UiTag(
                              uiHomeFeatureLabel(item.feature),
                              icon: uiFeatureIcon(item.feature),
                              tone: UiTagTone.primary,
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                // 不截断：窄屏大字时课程名或地点换行保留全文。
                                child: Text(
                                  subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                            // “待××”与时间信息重复，不显示。
                            if (!status.startsWith('待')) ...[
                              const SizedBox(width: 6),
                              UiTag(status),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                    Text(
                      item.timeLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: item.soon
                            ? UbaaTheme.warning(theme.colorScheme)
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.feature == FeatureId.signin) ...[
                const SizedBox(width: 8),
                Center(
                  child: FilledButton(
                    onPressed: signing ? null : onSignin ?? onRefreshSignin,
                    child: Text(
                      signing
                          ? '处理中…'
                          : onSignin != null
                          ? '签到'
                          : '刷新状态',
                    ),
                  ),
                ),
              ] else if (item.navigation != null)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
