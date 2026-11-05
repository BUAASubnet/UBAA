import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

/// 文件类型图标与配色，仅按扩展名推断展示，不参与任何协议判断。
(IconData, Color) bhpanTypeVisual(BhpanItem item, ColorScheme colors) {
  if (item.isFolder) return (Icons.folder_rounded, const Color(0xFFF2B53A));
  final name = item.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'pdf' => (Icons.picture_as_pdf_rounded, const Color(0xFFE5483B)),
    'doc' ||
    'docx' ||
    'rtf' ||
    'odt' => (Icons.description_rounded, const Color(0xFF2B6FD6)),
    'ppt' ||
    'pptx' ||
    'key' => (Icons.slideshow_rounded, const Color(0xFFE5772E)),
    'xls' ||
    'xlsx' ||
    'csv' ||
    'numbers' => (Icons.table_chart_rounded, const Color(0xFF1E8E4E)),
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' => (Icons.folder_zip_rounded, const Color(0xFF8D6E63)),
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'bmp' ||
    'svg' => (Icons.image_rounded, const Color(0xFF8E5CD9)),
    'mp4' ||
    'mov' ||
    'mkv' ||
    'avi' ||
    'webm' => (Icons.movie_rounded, const Color(0xFFD6336C)),
    'mp3' ||
    'wav' ||
    'flac' ||
    'm4a' ||
    'aac' => (Icons.audiotrack_rounded, const Color(0xFF0F9D9A)),
    'txt' || 'md' => (Icons.article_rounded, colors.onSurfaceVariant),
    'c' ||
    'cpp' ||
    'h' ||
    'java' ||
    'py' ||
    'rs' ||
    'dart' ||
    'js' ||
    'ts' ||
    'go' ||
    'html' ||
    'json' => (Icons.code_rounded, const Color(0xFF5B6FCB)),
    _ => (Icons.insert_drive_file_rounded, colors.outline),
  };
}

/// 列表用的短时间：今天 21:57、昨天 21:57、今年 3月13日、往年 2025-12-08。
String bhpanShortDate(DateTime time, {DateTime? now}) {
  final d = time.toUtc().add(const Duration(hours: 8));
  final n = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  final day = DateTime.utc(d.year, d.month, d.day),
      today = DateTime.utc(n.year, n.month, n.day);
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  if (d.year == n.year) return '${d.month}月${d.day}日';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class BhpanTypeIcon extends StatelessWidget {
  const BhpanTypeIcon({super.key, required this.item});
  final BhpanItem item;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = bhpanTypeVisual(item, Theme.of(context).colorScheme);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class BhpanItemTile extends StatelessWidget {
  const BhpanItemTile({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });
  final BhpanItem item;
  final bool selecting, selected, enabled;
  final VoidCallback onTap, onLongPress, onMore;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final meta = [
      if (!item.isFolder) bhpanBytes(item.bytes ?? 0),
      if (item.modifiedAt != null) bhpanShortDate(item.modifiedAt!),
    ].join(' · ');
    return Material(
      color: selected
          ? colors.secondaryContainer.withValues(alpha: .6)
          : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: selecting
                    ? Padding(
                        key: const ValueKey('check'),
                        padding: const EdgeInsets.only(right: 4),
                        child: Checkbox(
                          value: selected,
                          onChanged: enabled ? (_) => onTap() : null,
                        ),
                      )
                    : const SizedBox(key: ValueKey('none')),
              ),
              BhpanTypeIcon(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: '更多操作',
                  onPressed: enabled ? onMore : null,
                  icon: Icon(Icons.more_horiz, color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部操作面板：危险操作置底并以错误色显示。
Future<String?> bhpanActionSheet(
  BuildContext context, {
  required String title,
  required BhpanItem? item,
  required List<String> actions,
  required bool Function(String) enabled,
  Widget Function(Widget)? boundary,
}) {
  const icons = {
    '属性': Icons.info_outline,
    '重命名': Icons.drive_file_rename_outline,
    '移动': Icons.drive_file_move_outline,
    '复制': Icons.file_copy_outlined,
    '下载': Icons.download_outlined,
    '分享': Icons.ios_share,
    '分享记录': Icons.history,
    '另存到网盘': Icons.save_alt,
    '恢复': Icons.restore,
    '移入回收站': Icons.delete_outline,
    '永久删除': Icons.delete_forever_outlined,
  };
  const danger = {'移入回收站', '永久删除'};
  final ordered = [
    ...actions.where((a) => !danger.contains(a)),
    ...actions.where(danger.contains),
  ];
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      final sheet = SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: item == null ? null : BhpanTypeIcon(item: item),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              for (final a in ordered) ...[
                if (danger.contains(a) &&
                    a == ordered.firstWhere(danger.contains))
                  const Divider(height: 1),
                ListTile(
                  enabled: enabled(a),
                  leading: Icon(
                    icons[a] ?? Icons.chevron_right,
                    color: danger.contains(a) ? colors.error : null,
                  ),
                  title: Text(
                    a,
                    style: danger.contains(a)
                        ? TextStyle(color: colors.error)
                        : null,
                  ),
                  onTap: () => Navigator.pop(context, a),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return boundary == null ? sheet : boundary(sheet);
    },
  );
}

class BhpanBreadcrumb extends StatefulWidget {
  const BhpanBreadcrumb({
    super.key,
    required this.rootLabel,
    required this.names,
    required this.onRoot,
    required this.onIndex,
    required this.enabled,
  });
  final String rootLabel;
  final List<String> names;
  final VoidCallback onRoot;
  final ValueChanged<int> onIndex;
  final bool enabled;
  @override
  State<BhpanBreadcrumb> createState() => _BhpanBreadcrumbState();
}

class _BhpanBreadcrumbState extends State<BhpanBreadcrumb> {
  final _controller = ScrollController();
  @override
  void didUpdateWidget(covariant BhpanBreadcrumb old) {
    super.didUpdateWidget(old);
    if (old.names.length != widget.names.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients)
          _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget crumb(String text, VoidCallback? onTap, bool last) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: widget.enabled && !last ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: last ? colors.onSurface : colors.primary,
            fontWeight: last ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
    return SizedBox(
      height: 40,
      child: ListView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Center(
            child: crumb(widget.rootLabel, widget.onRoot, widget.names.isEmpty),
          ),
          for (final (i, name) in widget.names.indexed) ...[
            Icon(Icons.chevron_right, size: 18, color: colors.outline),
            Center(
              child: crumb(
                name,
                () => widget.onIndex(i),
                i == widget.names.length - 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BhpanStatePanel extends StatelessWidget {
  const BhpanStatePanel({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
