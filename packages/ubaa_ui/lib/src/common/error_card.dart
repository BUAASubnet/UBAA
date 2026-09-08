part of '../widgets.dart';

/// 统一错误卡片，避免将上游正文、URL 或堆栈直接展示给用户。
class FriendlyErrorCard extends StatelessWidget {
  const FriendlyErrorCard({required this.error, this.onRetry, super.key});

  final UiError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    error.title,
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error.message,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                  if (_safeIssueId != null) ...<Widget>[
                    const SizedBox(height: 8),
                    SelectableText('错误编号：$_safeIssueId'),
                    SelectableText('错误代码：${error.code.wireName}'),
                    TextButton.icon(
                      onPressed: () => _copyError(context),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('复制错误信息'),
                    ),
                  ],
                  if (error.retryable && onRetry != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onRetry,
                      child: Text(error.actionLabel ?? '重试'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? get _safeIssueId {
    final id = error.issueId;
    return id != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)
        ? id
        : null;
  }

  Future<void> _copyError(BuildContext context) async {
    final summary = <String>[
      '错误代码：${error.code.wireName}',
      '错误编号：$_safeIssueId',
      '错误类别：${error.kind.name}',
      if (error.resolvedRoute != null) '实际路线：${error.resolvedRoute!.name}',
    ].join('\n');
    await _copyDiagnosticText(context, summary);
  }
}

/// 复制是用户主动行为；平台剪贴板失败不向界面抛出异常。
Future<void> _copyDiagnosticText(BuildContext context, String text) async {
  var message = '已复制诊断信息';
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Object {
    message = '复制失败，请手动选择文字';
  }
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _showDiagnosticsDialog(
  BuildContext context,
  String Function() readDiagnostics,
) async {
  String report;
  try {
    report = readDiagnostics();
  } on Object {
    report = '当前无法读取诊断信息';
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('本次运行诊断'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: SelectableText(report)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () => _copyDiagnosticText(context, report),
          child: const Text('复制诊断信息'),
        ),
      ],
    ),
  );
}
