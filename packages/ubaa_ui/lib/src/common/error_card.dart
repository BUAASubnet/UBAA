import '../shared/feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ubaa_domain/ubaa_domain.dart';

/// 统一错误卡片，避免将上游正文、URL 或堆栈直接展示给用户。
class FriendlyErrorCard extends StatelessWidget {
  const FriendlyErrorCard({required this.error, this.onRetry, super.key});

  final UiError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fg = colors.onErrorContainer;
    final message = error.message.trim();
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    error.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!uiErrorMessageRestatesTitle(error.title, message)) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                  ],
                  if (_safeIssueId case final id?)
                    _ErrorDetails(
                      issueId: id,
                      code: error.code.wireName,
                      onCopy: () => _copyError(context),
                    ),
                  if (error.retryable && onRetry != null) ...<Widget>[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
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

/// 说明只是换一种说法重复标题时（“暂/暂时”、结尾“请稍后重试”）不再显示。
bool uiErrorMessageRestatesTitle(String title, String message) {
  String core(String text) => text
      .trim()
      .replaceAll(RegExp(r'[，,。.！!\s]*请稍后(再)?重试[。.！!]*$'), '')
      .replaceAll(RegExp(r'[。.！!]+$'), '')
      .replaceAll('暂时', '暂');
  final body = core(message);
  return body.isEmpty || body == core(title);
}

/// 错误编号默认收起；展开后以小字列出并提供复制。
class _ErrorDetails extends StatefulWidget {
  const _ErrorDetails({
    required this.issueId,
    required this.code,
    required this.onCopy,
  });
  final String issueId, code;
  final VoidCallback onCopy;

  @override
  State<_ErrorDetails> createState() => _ErrorDetailsState();
}

class _ErrorDetailsState extends State<_ErrorDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onErrorContainer;
    final small = theme.textTheme.bodySmall?.copyWith(color: fg);
    final compact = TextButton.styleFrom(
      foregroundColor: fg,
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: theme.textTheme.labelMedium,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        TextButton.icon(
          style: compact,
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
          label: const Text('错误详情'),
        ),
        if (_open) ...[
          SelectableText('错误编号：${widget.issueId}', style: small),
          SelectableText('错误代码：${widget.code}', style: small),
          TextButton.icon(
            style: compact,
            onPressed: widget.onCopy,
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('复制错误信息'),
          ),
        ],
      ],
    );
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
    UbaaFeedback.show(context, message);
  }
}

Future<void> uiShowDiagnosticsDialog(
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
