import 'package:flutter/material.dart';
import '../../shared/create_button.dart';

/// 「+」按钮：点开后在上方展开「上传文件」「新建文件夹」，点空白处收起。
class BhpanCreateMenu extends StatefulWidget {
  const BhpanCreateMenu({
    super.key,
    required this.enabled,
    this.onUpload,
    this.onNewFolder,
  });
  final bool enabled;
  final VoidCallback? onUpload, onNewFolder;
  @override
  State<BhpanCreateMenu> createState() => _BhpanCreateMenuState();
}

class _BhpanCreateMenuState extends State<BhpanCreateMenu>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool get _open => _controller.status != AnimationStatus.dismissed;

  @override
  void didUpdateWidget(covariant BhpanCreateMenu old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _open) _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() => _open ? _controller.reverse() : _controller.forward();

  void _pick(VoidCallback? action) {
    _controller.reverse();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    Widget option(String label, IconData icon, VoidCallback? action, Key key) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FloatingActionButton.extended(
            key: key,
            heroTag: null,
            elevation: 2,
            backgroundColor: colors.surfaceContainerHigh,
            foregroundColor: colors.onSurface,
            onPressed: action == null ? null : () => _pick(action),
            icon: Icon(icon),
            label: Text(label),
          ),
        );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Stack(
        children: [
          if (_open)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _controller.reverse,
                child: ColoredBox(
                  color: colors.scrim.withValues(alpha: .18 * curve.value),
                ),
              ),
            ),
          Positioned(
            right: ubaaCreateButtonMargin,
            bottom: ubaaCreateButtonMargin,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_open)
                  FadeTransition(
                    opacity: curve,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .3),
                        end: Offset.zero,
                      ).animate(curve),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (widget.onNewFolder != null)
                            option(
                              '新建文件夹',
                              Icons.create_new_folder_outlined,
                              widget.onNewFolder,
                              const ValueKey('bhpan-create-folder'),
                            ),
                          if (widget.onUpload != null)
                            option(
                              '上传文件',
                              Icons.upload_file,
                              widget.onUpload,
                              const ValueKey('bhpan-create-upload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ubaaCreateButton(
                  key: const ValueKey('bhpan-create'),
                  tooltip: _open ? '收起' : '上传或新建',
                  onPressed: widget.enabled ? _toggle : null,
                  open: curve,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
