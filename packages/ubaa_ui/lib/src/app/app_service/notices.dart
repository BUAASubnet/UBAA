import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 首页顶部的应用服务提示所需状态与操作，由宿主从控制器装配。
final class AppServiceNotices {
  const AppServiceNotices({
    this.update,
    this.banners = const [],
    required this.onOpenUrl,
    required this.onDismissUpdate,
    required this.onDismissAnnouncement,
  });

  /// 非同意状态或从未取得配置时为 null。
  final AppUpdateView? update;

  /// 只包含横幅级、未读且仍在有效期内的公告。
  final List<AppAnnouncement> banners;
  final Future<void> Function(Uri url) onOpenUrl;
  final Future<void> Function() onDismissUpdate;
  final Future<void> Function(String id) onDismissAnnouncement;

  bool get isEmpty =>
      banners.isEmpty &&
      !(update?.gateActive ?? false) &&
      !_showsAvailable(update);
}

bool _showsAvailable(AppUpdateView? update) =>
    update != null &&
    !update.gateActive &&
    update.status == AppUpdateStatus.updateAvailable &&
    !update.availableDismissed &&
    update.latestVersion != null;

/// 首页顶部的更新与公告横幅；门控横幅不可关闭并排在最前。
class AppServiceNoticeList extends StatelessWidget {
  const AppServiceNoticeList({super.key, required this.notices});
  final AppServiceNotices notices;

  @override
  Widget build(BuildContext context) {
    final update = notices.update;
    final url = update?.url;
    final items = <Widget>[
      if (update != null && update.gateActive)
        UpdateRequiredBanner(
          onUpdate: url == null
              ? null
              : () => unawaited(notices.onOpenUrl(url)),
        )
      else if (_showsAvailable(update))
        UpdateAvailableBanner(
          version: update!.latestVersion!,
          onOpen: () => unawaited(_openReleaseNotes(context, update)),
          onDismiss: () => unawaited(notices.onDismissUpdate()),
        ),
      for (final announcement in notices.banners)
        AnnouncementBanner(
          announcement: announcement,
          onOpenLink: switch (announcement.linkUrl) {
            final link? => () => unawaited(notices.onOpenUrl(link)),
            null => null,
          },
          onDismiss: () =>
              unawaited(notices.onDismissAnnouncement(announcement.id)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items) ...[item, const SizedBox(height: 12)],
      ],
    );
  }

  Future<void> _openReleaseNotes(
    BuildContext context,
    AppUpdateView update,
  ) async {
    final url = update.url;
    final go = await uiShowReleaseNotes(
      context,
      version: update.latestVersion!,
      notes: update.releaseNotes,
      canUpdate: url != null,
    );
    if (go && url != null) await notices.onOpenUrl(url);
  }
}

/// 首页顶部的应用服务提示：更新要求、新版本与公告横幅共用的外观。
class _HomeNotice extends StatelessWidget {
  const _HomeNotice({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    this.emphasis = false,
  });
  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;

  /// 更新要求使用错误容器色，其余提示使用普通容器色。
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final background = emphasis
        ? colors.errorContainer
        : colors.surfaceContainerHigh;
    final foreground = emphasis ? colors.onErrorContainer : colors.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: foreground),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                      if (body case final body?) ...[
                        const SizedBox(height: 4),
                        Text(
                          body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(children: actions),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 门控生效时的首页横幅：不可关闭，说明学校功能暂停、本机数据仍可查看。
class UpdateRequiredBanner extends StatelessWidget {
  const UpdateRequiredBanner({super.key, this.onUpdate});
  final VoidCallback? onUpdate;
  @override
  Widget build(BuildContext context) => _HomeNotice(
    key: const ValueKey('home-update-required'),
    icon: Icons.system_update_outlined,
    emphasis: true,
    title: '请更新 UBAA',
    body: '当前版本暂时无法访问学校服务，本机已保存的课表、日程和缓存内容仍可查看。',
    actions: [
      if (onUpdate != null)
        TextButton(onPressed: onUpdate, child: const Text('前往更新')),
    ],
  );
}

/// 有新版本但不强制更新时的首页横幅，可以忽略当前版本。
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.version,
    this.onOpen,
    this.onDismiss,
  });
  final String version;
  final VoidCallback? onOpen, onDismiss;
  @override
  Widget build(BuildContext context) => _HomeNotice(
    key: const ValueKey('home-update-available'),
    icon: Icons.new_releases_outlined,
    title: '发现新版本 $version',
    actions: [
      if (onOpen != null)
        TextButton(onPressed: onOpen, child: const Text('查看')),
      TextButton(onPressed: onDismiss, child: const Text('忽略')),
    ],
  );
}

/// 横幅级公告：可以关闭，关闭后记为已读。
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    this.onOpenLink,
    this.onDismiss,
  });
  final AppAnnouncement announcement;
  final VoidCallback? onOpenLink, onDismiss;
  @override
  Widget build(BuildContext context) => _HomeNotice(
    key: ValueKey('home-announcement-${announcement.id}'),
    icon: Icons.campaign_outlined,
    title: announcement.title,
    body: announcement.body,
    actions: [
      if (announcement.linkUrl != null && onOpenLink != null)
        TextButton(
          onPressed: onOpenLink,
          child: Text(announcement.linkText ?? '查看详情'),
        ),
      TextButton(onPressed: onDismiss, child: const Text('关闭')),
    ],
  );
}

/// 用户主动访问学校时被门控拒绝后的提示。返回 true 表示选择前往更新。
Future<bool> uiShowUpdateRequired(
  BuildContext context, {
  bool canUpdate = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('update-required-dialog'),
        icon: const Icon(Icons.system_update_outlined),
        title: const Text('需要更新'),
        content: const Text('当前版本暂时无法访问学校服务，请更新后再试。本机已保存的内容仍可查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          if (canUpdate)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('前往更新'),
            ),
        ],
      ),
    ) ==
    true;

/// 新版本说明。返回 true 表示选择前往更新。
Future<bool> uiShowReleaseNotes(
  BuildContext context, {
  required String version,
  String? notes,
  bool canUpdate = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新版本 $version'),
        scrollable: true,
        content: Text(
          (notes == null || notes.trim().isEmpty) ? '暂无更新说明。' : notes,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          if (canUpdate)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('前往更新'),
            ),
        ],
      ),
    ) ==
    true;

/// 弹窗级公告：只能通过确认按钮关闭。返回 true 表示用户已确认，调用方据此记为已读；
/// 弹窗被其他原因移除时返回 false，下次仍会显示。
Future<bool> uiShowAnnouncement(
  BuildContext context,
  AppAnnouncement announcement, {
  VoidCallback? onOpenLink,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: ValueKey('announcement-dialog-${announcement.id}'),
          title: Text(announcement.title),
          scrollable: true,
          content: SelectableText(announcement.body),
          actions: [
            if (announcement.linkUrl != null && onOpenLink != null)
              TextButton(
                onPressed: onOpenLink,
                child: Text(announcement.linkText ?? '查看详情'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(announcement.confirmText ?? '知道了'),
            ),
          ],
        ),
      ),
    ) ==
    true;
