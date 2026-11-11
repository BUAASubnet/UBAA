import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../../common/section.dart';
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/layout/rail_identity.dart' show UiAppIcon;

/// “我的”：身份、校园账户与校园网流量。
///
/// 数据未接入时各项显示占位；单项失败只影响对应位置。
class MeView extends StatelessWidget {
  const MeView({
    super.key,
    required this.user,
    this.overview,
    this.showShortcuts = true,
    this.onOpenProfile,
    this.onOpenSettings,
    this.onOpenAbout,
    this.onLogout,
    this.onOpenBhpan,
  });

  final UserSummary? user;
  final CampusAccountOverview? overview;

  /// 窄屏没有侧边栏，在页尾提供设置、关于和退出。
  final bool showShortcuts;
  final VoidCallback? onOpenProfile, onOpenSettings, onOpenAbout, onLogout;
  final VoidCallback? onOpenBhpan;

  @override
  Widget build(BuildContext context) {
    final overview = this.overview ?? const CampusAccountOverview();
    return ListView(
      key: const PageStorageKey<String>('me-page'),
      padding: UbaaTheme.pageInsets(context, top: 8),
      children: [
        _IdentityHeader(
          key: const ValueKey('me-profile'),
          user: user,
          identity: overview.identity,
          onTap: onOpenProfile,
        ),
        const SizedBox(height: 24),
        const UiSectionTitle('校园账户'),
        _MetricsPanel(section: overview.metrics, onOpenBhpan: onOpenBhpan),
        const SizedBox(height: 24),
        const UiSectionTitle('校园网流量'),
        _NetworkPanel(section: overview.network),
        if (showShortcuts) ...[
          const SizedBox(height: 24),
          _Shortcuts(
            onOpenSettings: onOpenSettings,
            onOpenAbout: onOpenAbout,
            onLogout: onLogout,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    super.key,
    required this.user,
    required this.identity,
    this.onTap,
  });
  final UserSummary? user;
  final CampusSection<PortalIdentity> identity;

  /// 打开“我的资料”；卡片末尾的箭头提示可以点开。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = this.user;
    final name = uiNonBlank(user?.preferredName) ?? '未登录';
    final studentId = uiNonBlank(user?.schoolId) ?? uiNonBlank(user?.username);
    final portal = identity.data;
    final department =
        uiNonBlank(portal?.department) ?? uiNonBlank(user?.department);
    final tags = <String>[?uiNonBlank(portal?.identity), ?department];
    Widget tag(String text) => DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // 已登录显示姓氏头像；未登录时退回应用图标。
              if (uiNonBlank(user?.preferredName) case final display?)
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    String.fromCharCode(display.runes.first).toUpperCase(),
                    textScaler: TextScaler.noScaling,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                const UiAppIcon(size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    if (studentId != null && studentId != name) ...[
                      const SizedBox(height: 2),
                      Text(
                        studentId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ],
                    // 身份与学院横排在学号下方，长学院名换行而不挤压姓名。
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final text in tags) tag(text)],
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个指标在界面上的状态。
sealed class _TileValue {
  const _TileValue();
}

class _TileText extends _TileValue {
  const _TileText(
    this.value, {
    this.unit,
    this.prefix,
    this.emphasis = false,
    this.low = false,
  });
  final String value;
  final String? unit, prefix;
  final bool emphasis;

  /// 余额偏低，用提醒色显示。
  final bool low;
}

class _TileFailed extends _TileValue {
  const _TileFailed();
}

class _TilePending extends _TileValue {
  const _TilePending({required this.loading});
  final bool loading;
}

/// 容量单位统一写成 GB、MB、KB；上游只给单个字母时补全，其余原样显示。
String? _unit(String raw) => switch (uiNonBlank(raw)) {
  final unit? when const {'G', 'M', 'K', 'T'}.contains(unit.toUpperCase()) =>
    '${unit.toUpperCase()}B',
  final other => other,
};

/// 上游可能返回未舍入的浮点值（如 10.659999999999998），只在显示时保留两位。
/// [fixed] 为金额补足两位；其余数量舍入后省略末尾零。
String _decimal(String raw, {bool fixed = false}) {
  // 用十进制整数舍入，避免 double 损失大金额的整数位。
  final match = RegExp(
    r'^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(raw);
  if (match == null) return raw;
  final fraction = match[3] ?? '';
  final exponent = int.tryParse(match[4] ?? '0');
  if (exponent == null || exponent.abs() > 100) return raw;
  var scaled = BigInt.parse('${match[2]}$fraction');
  final shift = fraction.length - exponent - 2;
  if (shift > 0) {
    final divisor = BigInt.from(10).pow(shift);
    scaled = (scaled + divisor ~/ BigInt.two) ~/ divisor;
  } else {
    scaled *= BigInt.from(10).pow(-shift);
  }
  final digits = scaled.toString().padLeft(3, '0');
  final sign = match[1] == '-' && scaled != BigInt.zero ? '-' : '';
  final text =
      '$sign${digits.substring(0, digits.length - 2)}.${digits.substring(digits.length - 2)}';
  return fixed ? text : text.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.section, this.onOpenBhpan});
  final CampusSection<CampusMetrics> section;
  final VoidCallback? onOpenBhpan;

  _TileValue _amount(CampusMetric<CampusAmount>? metric, {bool money = false}) {
    return switch (metric) {
      CampusMetricValue(:final value) =>
        money && (value.unit.isEmpty || value.unit == '元')
            ? _TileText(
                _decimal(value.value, fixed: true),
                prefix: '¥',
                // 不足十元时提醒充值。
                low: (double.tryParse(value.value) ?? double.infinity) < 10,
              )
            : _TileText(_decimal(value.value), unit: _unit(value.unit)),
      CampusMetricFailure() => const _TileFailed(),
      null =>
        section.error != null
            ? const _TileFailed()
            : _TilePending(loading: section.loading),
    };
  }

  _TileValue _count(CampusMetric<int>? metric, String unit) {
    return switch (metric) {
      CampusMetricValue(:final value) => _TileText(
        '$value',
        unit: unit,
        emphasis: value > 0,
      ),
      CampusMetricFailure() => const _TileFailed(),
      null =>
        section.error != null
            ? const _TileFailed()
            : _TilePending(loading: section.loading),
    };
  }

  @override
  Widget build(BuildContext context) {
    final metrics = section.data;
    final balances = [
      _MetricTile(
        key: const ValueKey('me-metric-card'),
        icon: Icons.credit_card_outlined,
        label: '校园卡',
        value: _amount(metrics?.cardBalance, money: true),
        large: true,
      ),
      _MetricTile(
        key: const ValueKey('me-metric-network-fee'),
        icon: Icons.wifi_outlined,
        label: '网费',
        value: _amount(metrics?.networkBalance, money: true),
        large: true,
      ),
    ];
    final counts = [
      _MetricTile(
        key: const ValueKey('me-metric-mail'),
        icon: Icons.mail_outline,
        label: '未读邮件',
        value: _count(metrics?.unreadMail, '封'),
      ),
      _MetricTile(
        key: const ValueKey('me-metric-books'),
        icon: Icons.menu_book_outlined,
        label: '待还图书',
        value: _count(metrics?.borrowedBooks, '本'),
      ),
      _MetricTile(
        key: const ValueKey('me-metric-cloud'),
        icon: Icons.cloud_outlined,
        // 窄卡片还要放箭头，两字标签不被截断。
        label: '云盘',
        value: _amount(metrics?.cloudStorageRemaining),
        onTap: onOpenBhpan,
      ),
    ];
    Widget row(List<Widget> tiles) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tile),
          ],
        ],
      ),
    );
    final error = section.error;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (constraints.maxWidth >= 760)
            row([...balances, ...counts])
          else if (MediaQuery.textScalerOf(context).scale(10) > 13) ...[
            // 大字号下三列放不下标签，改为两列。
            row(balances),
            const SizedBox(height: 12),
            row(counts.sublist(0, 2)),
            const SizedBox(height: 12),
            row([counts[2], const SizedBox.shrink()]),
          ] else ...[
            row(balances),
            const SizedBox(height: 12),
            row(counts),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            _InlineNotice(error),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.large = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final _TileValue value;
  final bool large;

  /// 可点开的指标（如云盘）在标签行末尾显示箭头。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle =
        (large ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w500);
    final unitStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final valueLineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((valueStyle?.fontSize ?? 22) * 1.3);
    final Widget display = switch (value) {
      _TileText(
        :final value,
        :final unit,
        :final prefix,
        :final emphasis,
        :final low,
      ) =>
        Text.rich(
          TextSpan(
            children: [
              if (prefix != null) TextSpan(text: '$prefix ', style: unitStyle),
              TextSpan(
                text: value,
                style: valueStyle?.copyWith(
                  color: low
                      ? UbaaTheme.warning(scheme)
                      : emphasis
                      ? scheme.primary
                      : null,
                ),
              ),
              if (unit != null) TextSpan(text: ' $unit', style: unitStyle),
            ],
          ),
          maxLines: 1,
        ),
      _TileFailed() => Text(
        '读取失败',
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
      ),
      // 读取进度只在标题栏右上角显示，卡片内保持中性的占位。
      _TilePending() => Text(
        '—',
        style: valueStyle?.copyWith(color: scheme.outline),
      ),
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
              SizedBox(height: large ? 12 : 10),
              // 数值行固定高度：数值、读取中、失败之间切换时卡片不跳动，
              // 并避免缩放文本在等高行内报告不一致的固有高度。
              SizedBox(
                height: valueLineHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.bottomStart,
                  child: display,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.section});
  final CampusSection<NetworkUsage> section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = section.data;
    final children = <Widget>[];
    if (usage != null && usage.products.isNotEmpty) {
      for (final (i, product) in usage.products.indexed) {
        if (i > 0) children.add(const SizedBox(height: 12));
        children.add(_NetworkProductCard(product: product));
      }
    } else {
      children.add(
        Card.outlined(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.network_check_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.loading
                        ? '—'
                        : usage != null
                        ? '当前账号没有网络产品'
                        : '暂无流量数据',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (section.error case final error?) {
      children.add(const SizedBox(height: 8));
      children.add(_InlineNotice(error));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _NetworkProductCard extends StatelessWidget {
  const _NetworkProductCard({required this.product});
  final NetworkProductUsage product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget figure(String label, CampusAmount amount, {bool primary = false}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _decimal(amount.value),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: primary ? scheme.primary : null,
                        ),
                      ),
                      if (_unit(amount.unit) case final unit?)
                        TextSpan(
                          text: ' $unit',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );
    final used = double.tryParse(product.used.value);
    final free = double.tryParse(product.freeRemaining.value);
    final freeProgress =
        used != null &&
            free != null &&
            used >= 0 &&
            free >= 0 &&
            used + free > 0 &&
            product.used.unit == product.freeRemaining.unit
        ? used / (used + free)
        : null;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.router_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                figure('已用', product.used),
                const SizedBox(width: 12),
                figure('免费剩余', product.freeRemaining, primary: true),
                const SizedBox(width: 12),
                figure('计费剩余', product.billableRemaining),
              ],
            ),
            // 免费额度的使用进度：已用 ÷（已用 + 免费剩余）。
            if (freeProgress case final progress?) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: progress >= .9
                      ? UbaaTheme.warning(scheme)
                      : scheme.primary,
                  semanticsLabel: '免费流量已用',
                  semanticsValue: '${(progress * 100).round()}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({this.onOpenSettings, this.onOpenAbout, this.onLogout});
  final VoidCallback? onOpenSettings, onOpenAbout, onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            key: const ValueKey('me-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenSettings,
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            key: const ValueKey('me-about'),
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenAbout,
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            key: const ValueKey('me-logout'),
            iconColor: scheme.error,
            textColor: scheme.error,
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
