import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'chrome.dart';
import 'format.dart';
import '../../shared/loading.dart';

/// 条目可执行的操作；标签与图标只在这里维护。
enum BhpanAction {
  view('查看', Icons.visibility_outlined),
  download('下载', Icons.download_outlined),
  share('分享', Icons.ios_share),
  move('移动', Icons.drive_file_move_outline),
  rename('重命名', Icons.drive_file_rename_outline),
  copy('复制到', Icons.file_copy_outlined),
  saveToMine('保存到我的网盘', Icons.save_alt),
  details('详细信息', Icons.info_outline),
  shareRecords('分享记录', Icons.history),
  restore('恢复', Icons.restore),
  recycle('移入回收站', Icons.delete_outline, danger: true),
  deleteForever('永久删除', Icons.delete_forever_outlined, danger: true);

  const BhpanAction(this.label, this.icon, {this.danger = false});
  final String label;
  final IconData icon;
  final bool danger;
}

/// 面板顶部最多四个快捷操作，其余操作以列表展示。
const _quick = [
  BhpanAction.download,
  BhpanAction.share,
  BhpanAction.move,
  BhpanAction.rename,
];

String bhpanTypeName(BhpanItem item) {
  if (item.isFolder) return '文件夹';
  final name = item.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'pdf' => 'PDF 文档',
    'doc' || 'docx' => 'Word 文档',
    'ppt' || 'pptx' => 'PowerPoint 演示文稿',
    'xls' || 'xlsx' => 'Excel 表格',
    'csv' => 'CSV 表格',
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => '压缩包',
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'heic' || 'bmp' => '图片',
    'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' => '视频',
    'mp3' || 'wav' || 'flac' || 'm4a' || 'aac' => '音频',
    'txt' || 'md' => '文本',
    '' => '文件',
    _ => '${ext.toUpperCase()} 文件',
  };
}

Widget _sheetHeader(
  BuildContext context,
  BhpanItem item, {
  String? location,
  double iconSize = 48,
}) {
  final theme = Theme.of(context);
  final meta = [
    bhpanItemMeta(item),
    if (location != null) location,
  ].where((s) => s.isNotEmpty).join(' · ');
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Row(
      children: [
        BhpanTypeIcon(item: item, size: iconSize),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 条目「更多操作」：快捷操作一行，其余列表，危险操作置底并以错误色显示。
Future<BhpanAction?> bhpanActionSheet(
  BuildContext context, {
  required BhpanItem item,
  required List<BhpanAction> actions,
  required bool Function(BhpanAction) enabled,
  String? location,
  Widget Function(Widget)? boundary,
}) => showModalBottomSheet<BhpanAction>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quick = [
      for (final a in _quick)
        if (actions.contains(a)) a,
    ];
    final rest = [
      for (final a in actions)
        if (!quick.contains(a) && !a.danger) a,
    ];
    final danger = [
      for (final a in actions)
        if (a.danger) a,
    ];
    Widget quickButton(BhpanAction a) {
      final on = enabled(a);
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: on ? () => Navigator.pop(context, a) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(
                      alpha: on ? .7 : .3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    a.icon,
                    color: on
                        ? colors.onSecondaryContainer
                        : colors.onSurface.withValues(alpha: .38),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  a.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: on ? null : colors.onSurface.withValues(alpha: .38),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget tile(BhpanAction a) => ListTile(
      key: ValueKey('bhpan-action-${a.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      enabled: enabled(a),
      leading: Icon(a.icon, color: a.danger ? colors.error : null),
      title: Text(
        a.label,
        style: a.danger ? TextStyle(color: colors.error) : null,
      ),
      onTap: () => Navigator.pop(context, a),
    );
    final sheet = SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader(context, item, location: location),
            if (quick.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(children: [for (final a in quick) quickButton(a)]),
              ),
            if (rest.isNotEmpty) ...[
              const Divider(height: 1),
              for (final a in rest) tile(a),
            ],
            if (danger.isNotEmpty) ...[
              const Divider(height: 1),
              for (final a in danger) tile(a),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    return boundary == null ? sheet : boundary(sheet);
  },
);

/// 详细信息：文件直接展示已知字段，文件夹另行统计内容；可附带主要操作按钮。
Future<BhpanAction?> showBhpanDetails(
  BuildContext context, {
  required BhpanItem item,
  String? location,
  Future<BhpanSize> Function()? folderSize,
  List<BhpanAction> primary = const [],
  bool Function(BhpanAction)? enabled,
  Widget Function(Widget)? boundary,
}) => showModalBottomSheet<BhpanAction>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final sheet = _DetailsSheet(
      item: item,
      location: location,
      folderSize: item.isFolder ? folderSize : null,
      primary: primary,
      enabled: enabled ?? (_) => true,
    );
    return boundary == null ? sheet : boundary(sheet);
  },
);

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.item,
    required this.location,
    required this.folderSize,
    required this.primary,
    required this.enabled,
  });
  final BhpanItem item;
  final String? location;
  final Future<BhpanSize> Function()? folderSize;
  final List<BhpanAction> primary;
  final bool Function(BhpanAction) enabled;
  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final Future<BhpanSize>? _size = widget.folderSize?.call();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = widget.item;
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    Widget text(String value) =>
        SelectableText(value, style: theme.textTheme.bodyMedium);
    final buttons = [
      for (final (i, a) in widget.primary.indexed)
        Expanded(
          child: i == 0
              ? FilledButton.icon(
                  onPressed: widget.enabled(a)
                      ? () => Navigator.pop(context, a)
                      : null,
                  icon: Icon(a.icon),
                  label: Text(a.label),
                )
              : FilledButton.tonalIcon(
                  onPressed: widget.enabled(a)
                      ? () => Navigator.pop(context, a)
                      : null,
                  icon: Icon(a.icon),
                  label: Text(a.label),
                ),
        ),
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader(context, item, iconSize: 56),
            const Divider(height: 1),
            const SizedBox(height: 8),
            row('类型', text(bhpanTypeName(item))),
            if (!item.isFolder && item.bytes != null)
              row('大小', text(bhpanBytes(item.bytes!))),
            if (_size case final size?)
              row(
                '内容',
                FutureBuilder<BhpanSize>(
                  future: size,
                  builder: (context, snap) => snap.hasData
                      ? text(
                          '${snap.data!.folders} 个文件夹、${snap.data!.files} 个文件，共 ${bhpanBytes(snap.data!.bytes)}',
                        )
                      : snap.hasError
                      ? text('暂时无法统计')
                      : const Align(
                          alignment: Alignment.centerLeft,
                          child: LoadingGlyph(dimension: 16),
                        ),
                ),
              ),
            if (item.modifiedAt != null)
              row('修改时间', text(bhpanDate(item.modifiedAt!))),
            if (item.createdAt != null)
              row('创建时间', text(bhpanDate(item.createdAt!))),
            if (widget.location != null) row('位置', text(widget.location!)),
            if (buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    for (final (i, b) in buttons.indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      b,
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
