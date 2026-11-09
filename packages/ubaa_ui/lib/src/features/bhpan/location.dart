import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/sheet.dart';

/// 「位置」面板的选择：切换文档库，或进入回收站、分享管理、打开分享链接。
sealed class BhpanPlaceChoice {
  const BhpanPlaceChoice();
}

final class BhpanLibraryChoice extends BhpanPlaceChoice {
  const BhpanLibraryChoice(this.kind);
  final BhpanRootKind kind;
}

enum BhpanTool { shares, recycle, openLink }

final class BhpanToolChoice extends BhpanPlaceChoice {
  const BhpanToolChoice(this.tool);
  final BhpanTool tool;
}

const bhpanLibraryNames = {
  BhpanRootKind.personal: '个人文档库',
  BhpanRootKind.shared: '共享文档库',
  BhpanRootKind.department: '部门文档库',
  BhpanRootKind.group: '群组文档库',
  BhpanRootKind.all: '全部文档库',
};

const bhpanLibraryIcons = {
  BhpanRootKind.personal: Icons.person_outline,
  BhpanRootKind.shared: Icons.folder_shared_outlined,
  BhpanRootKind.department: Icons.apartment_outlined,
  BhpanRootKind.group: Icons.groups_outlined,
  BhpanRootKind.all: Icons.dashboard_outlined,
};

/// 当前位置只用一行表达：位置按钮 + 可横向滚动的路径 + 少量工具按钮。
class BhpanLocationBar extends StatefulWidget {
  const BhpanLocationBar({
    super.key,
    required this.rootLabel,
    required this.rootIcon,
    required this.names,
    required this.enabled,
    required this.onPlaces,
    required this.onRoot,
    required this.onIndex,
    this.actions = const [],
  });
  final String rootLabel;
  final IconData rootIcon;
  final List<String> names;
  final bool enabled;
  final VoidCallback onPlaces, onRoot;
  final ValueChanged<int> onIndex;
  final List<Widget> actions;
  @override
  State<BhpanLocationBar> createState() => _BhpanLocationBarState();
}

class _BhpanLocationBarState extends State<BhpanLocationBar> {
  final _controller = ScrollController();
  @override
  void didUpdateWidget(covariant BhpanLocationBar old) {
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
    Widget crumb(String text, VoidCallback onTap, bool last) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.enabled && !last ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: ConstrainedBox(
          // 当前目录放宽，中间层级收短，避免长目录名在空位充足时也被截断。
          constraints: BoxConstraints(maxWidth: last ? 360 : 160),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: last ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: last ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
    final atRoot = widget.names.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Material(
            color: colors.secondaryContainer.withValues(alpha: .6),
            shape: const StadiumBorder(),
            child: InkWell(
              key: const ValueKey('bhpan-places'),
              customBorder: const StadiumBorder(),
              onTap: widget.enabled ? widget.onPlaces : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.rootIcon,
                      size: 18,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.rootLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: atRoot ? FontWeight.w500 : null,
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 20,
                      color: colors.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 2),
                children: [
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
            ),
          ),
          ...widget.actions,
        ],
      ),
    );
  }
}

/// 位置面板：上半部分切换文档库，下半部分进入云盘工具。
Future<BhpanPlaceChoice?> showBhpanPlaces(
  BuildContext context, {
  required BhpanRootKind? current,
  Widget Function(Widget)? boundary,
}) => showUiSheet<BhpanPlaceChoice>(
  context,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    Widget tile(
      IconData icon,
      String label,
      BhpanPlaceChoice choice, {
      bool selected = false,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: selected ? colors.primary : null),
      title: Text(
        label,
        style: selected
            ? TextStyle(color: colors.primary, fontWeight: FontWeight.w500)
            : null,
      ),
      trailing: selected ? Icon(Icons.check, color: colors.primary) : null,
      selected: selected,
      onTap: () => Navigator.pop(context, choice),
    );
    final sheet = UiSheetBody(
      title: '切换位置',
      children: [
        header('文档库'),
        for (final kind in const [
          BhpanRootKind.personal,
          BhpanRootKind.shared,
          BhpanRootKind.department,
          BhpanRootKind.group,
          BhpanRootKind.all,
        ])
          tile(
            bhpanLibraryIcons[kind]!,
            bhpanLibraryNames[kind]!,
            BhpanLibraryChoice(kind),
            selected: kind == current,
          ),
        const Divider(),
        header('工具'),
        tile(Icons.link, '分享管理', const BhpanToolChoice(BhpanTool.shares)),
        tile(
          Icons.delete_outline,
          '回收站',
          const BhpanToolChoice(BhpanTool.recycle),
        ),
        tile(
          Icons.move_to_inbox_outlined,
          '打开分享链接',
          const BhpanToolChoice(BhpanTool.openLink),
        ),
      ],
    );
    return boundary == null ? sheet : boundary(sheet);
  },
);
