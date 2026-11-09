import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme.dart' show UbaaTheme;
import '../../write/forms/action_bar.dart' show FormActionBar;
import 'sheet.dart' show uiPrefersDialog;

/// 编辑表单与子页面的统一入口：窄窗口整页推入；宽窗口为居中对话框，不盖住侧边栏。
///
/// [fixedHeight] 用于回收站、文件夹选择这类可滚动浏览的子页面：对话框取固定高度，
/// 页面内的 Scaffold 照常布局；表单默认按内容高度收缩。表单点外面不关闭，避免误丢输入。
Future<T?> showUiPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double dialogWidth = 560,
  bool fixedHeight = false,
  bool? dismissible,
}) {
  if (!uiPrefersDialog(context)) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible ?? fixedHeight,
    builder: (context) {
      final height = math.min(MediaQuery.sizeOf(context).height * .88, 820.0);
      final theme = Theme.of(context);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: height,
            minHeight: fixedHeight ? height : 0,
          ),
          child: Theme(
            // 对话框里的页面返回键显示为关闭。
            // 页面底色与其他对话框一致。
            data: theme.copyWith(
              scaffoldBackgroundColor: theme.colorScheme.surfaceContainerLow,
              appBarTheme: theme.appBarTheme.copyWith(
                backgroundColor: theme.colorScheme.surfaceContainerLow,
              ),
              actionIconTheme: ActionIconThemeData(
                backButtonIconBuilder: (_) => const Icon(Icons.close),
              ),
            ),
            child: _UiDialogPageScope(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 当前内容是否由 [showUiPage] 以对话框形式显示。
bool uiInDialogPage(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_UiDialogPageScope>() != null;

class _UiDialogPageScope extends InheritedWidget {
  const _UiDialogPageScope({required super.child});
  @override
  bool updateShouldNotify(_UiDialogPageScope oldWidget) => false;
}

/// 表单骨架：标题、可滚动字段、错误提示与底部操作。
///
/// 整页时是标题栏加底部操作栏；对话框时标题行右侧带关闭，操作按钮靠右，
/// 主要操作在最右，与新建日程一致。
class UiFormScaffold extends StatelessWidget {
  const UiFormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.primary,
    this.secondary,
    this.onClose,
    this.error,
    this.hint,
    this.listKey,
    this.flush = false,
  });
  final String title;
  final List<Widget> children;

  /// 主要操作，通常是 [FilledButton]。
  final Widget primary;

  /// 次要操作（取消、返回修改等）。
  final Widget? secondary;

  /// 关闭或返回；默认弹出当前页面。
  final VoidCallback? onClose;
  final String? error;

  /// 对话框底部左侧的小字说明，整页时放在字段末尾。
  final String? hint;
  final Key? listKey;

  /// 字段自带 16 像素左右边距（如整行的 ListTile），外层不再加页边距。
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final close = onClose ?? () => Navigator.maybePop(context);
    final errorText = error == null
        ? null
        : Text(error!, style: TextStyle(color: colors.error));
    final hintText = hint == null
        ? null
        : Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          );
    if (uiInDialogPage(context)) {
      return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                key: listKey,
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(
                  flush ? 8 : 24,
                  8,
                  flush ? 8 : 24,
                  8,
                ),
                children: children,
              ),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: errorText,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  Expanded(child: hintText ?? const SizedBox.shrink()),
                  if (secondary != null) ...[
                    secondary!,
                    const SizedBox(width: 8),
                  ],
                  primary,
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        leading: BackButton(onPressed: close),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              key: listKey,
              padding: flush
                  ? const EdgeInsets.symmetric(vertical: 8)
                  : EdgeInsets.all(
                      UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
                    ),
              children: [...children, ?hintText],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FormActionBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: errorText,
                ),
              Row(
                children: [
                  if (secondary != null) ...[
                    Expanded(child: secondary!),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 50),
                      child: primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表单里的分组：小标题加字段，不加底色，分组之间靠留白区分。
class UiFormSection extends StatelessWidget {
  const UiFormSection({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.padding = EdgeInsets.zero,
  });
  final String? title;

  /// 标题下的一行小字说明（如留空时的默认行为）。
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 2),
              Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    );
  }
}
