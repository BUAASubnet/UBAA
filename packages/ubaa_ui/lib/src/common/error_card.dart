import '../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import 'feedback_notice.dart' show uiShowFeedbackNotice;
import 'app_links.dart' show uiShowAppLinkFailure;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ubaa_domain/ubaa_domain.dart';

/// 所有错误卡共用本次运行的安全诊断出口，包括弹窗中的错误卡。
class UiDiagnosticsScope extends InheritedWidget {
  const UiDiagnosticsScope({
    required this.readRecord,
    this.exportReport,
    this.exportLabel = '分享报告文件',
    this.openFeedback,
    required super.child,
    super.key,
  });
  final String? Function(String issueId) readRecord;
  final Future<String?> Function(String report)? exportReport;
  final String exportLabel;
  final Future<bool> Function()? openFeedback;

  static UiDiagnosticsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiDiagnosticsScope>();

  @override
  bool updateShouldNotify(UiDiagnosticsScope oldWidget) =>
      readRecord != oldWidget.readRecord ||
      exportReport != oldWidget.exportReport ||
      exportLabel != oldWidget.exportLabel ||
      openFeedback != oldWidget.openFeedback;
}

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
    final diagnostics = UiDiagnosticsScope.of(context);
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (!uiErrorMessageRestatesTitle(error.title, message)) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                  ],
                  if (_safeIssueId(error) case final id?)
                    _ErrorDetails(
                      issueId: id,
                      code: error.code.wireName,
                      onCopy: () => _copyDiagnosticText(
                        context,
                        _errorReport(diagnostics, error, id),
                      ),
                      share: diagnostics?.exportReport == null
                          ? null
                          : _ReportExportButton(
                              report: () =>
                                  _errorReport(diagnostics, error, id),
                              export: diagnostics!.exportReport!,
                              label: diagnostics.exportLabel,
                            ),
                      onFeedback: diagnostics?.openFeedback == null
                          ? null
                          : uiErrorDetailsAction(context, error),
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
}

String? _safeIssueId(UiError error) {
  final id = error.issueId;
  return id != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)
      ? id
      : null;
}

String _errorReport(UiDiagnosticsScope? scope, UiError error, String id) {
  try {
    if (scope?.readRecord(id) case final report?) return report;
  } on Object {
    // 记录无法读取时仍可提取安全摘要。
  }
  return const JsonEncoder.withIndent('  ').convert({
    'record_available': false,
    'issue_id': id,
    'code': error.code.wireName,
    'kind': error.kind.name,
    'retryable': error.retryable,
    if (error.authStage case final stage?) 'stage': stage.wireName,
    if (error.authReason case final reason?) 'reason': reason.wireName,
    if (error.resolvedRoute case final route?) 'route': route.name,
    if (error.diagnostic case final diagnostic?)
      'diagnostic': diagnostic.toJson(),
  });
}

/// 行内状态与短提示使用同一个报告入口。
VoidCallback? uiErrorDetailsAction(BuildContext context, UiError? error) {
  if (error == null || _safeIssueId(error) == null) return null;
  return () {
    if (context.mounted) unawaited(uiShowErrorDetails(context, error));
  };
}

Future<void> uiShowErrorDetails(BuildContext context, UiError error) async {
  final id = _safeIssueId(error);
  if (id == null) return;
  final scope = UiDiagnosticsScope.of(context);
  await uiShowDiagnosticsDialog(context, () => _errorReport(scope, error, id));
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
    this.share,
    this.onFeedback,
  });
  final String issueId, code;
  final VoidCallback onCopy;
  final Widget? share;
  final VoidCallback? onFeedback;

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
          if (widget.share != null) widget.share!,
          if (widget.onFeedback != null)
            TextButton.icon(
              style: compact,
              onPressed: widget.onFeedback,
              icon: const Icon(Icons.feedback_outlined, size: 16),
              label: const Text('诊断与反馈'),
            ),
        ],
      ],
    );
  }
}

/// 复制是用户主动行为；平台剪贴板失败不向界面抛出异常。
Future<void> _copyDiagnosticText(BuildContext context, String text) async {
  var message = '已复制错误信息';
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Object {
    message = '复制失败，请手动选择文字';
  }
  if (context.mounted) {
    if (ScaffoldMessenger.maybeOf(context) case final messenger?)
      uiShowFeedbackNotice(messenger, message);
  }
}

Future<void> uiShowDiagnosticsDialog(
  BuildContext context,
  String Function() readDiagnostics,
) async {
  String? readReport() {
    try {
      return readDiagnostics();
    } on Object {
      return null;
    }
  }

  final report = readReport() ?? '当前无法读取诊断信息';
  final scope = UiDiagnosticsScope.of(context);
  await showUiSheet<void>(
    context,
    builder: (context) => UiSheetBody(
      title: '诊断信息',
      actions: [
        if (scope?.exportReport != null)
          _ReportExportButton(
            report: readReport,
            export: scope!.exportReport!,
            label: scope.exportLabel,
          ),
      ],
      primaryAction: FilledButton.icon(
        onPressed: () => _copyDiagnosticText(context, readReport() ?? report),
        icon: const Icon(Icons.copy_outlined, size: 18),
        label: const Text('复制诊断信息'),
      ),
      // 诊断内容是 JSON：等宽字体放在浅色底框里，便于阅读和复制。
      children: [
        if (scope?.openFeedback case final openFeedback?) ...[
          const Text(
            '完整诊断包含学校原始响应，可能含个人数据和登录凭据，请仅发送给可信任的维护者。复制诊断信息仅包含错误摘要。打开分享面板或保存文件不会提交反馈。',
          ),
          TextButton.icon(
            onPressed: () => unawaited(_openFeedback(context, openFeedback)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开反馈页面'),
          ),
          const SizedBox(height: 8),
        ],
        Builder(
          builder: (context) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              report,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['monospace', 'Courier'],
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _openFeedback(
  BuildContext context,
  Future<bool> Function() open,
) async {
  try {
    if (await open()) return;
  } on Object {
    // 系统浏览器不可用时提供可复制的地址。
  }
  if (context.mounted) await uiShowAppLinkFailure(context, AppLink.feedback);
}

/// 一次只打开一个系统面板；失败后仍可复制报告。
class _ReportExportButton extends StatefulWidget {
  const _ReportExportButton({
    required this.report,
    required this.export,
    required this.label,
  });
  final String? Function() report;
  final Future<String?> Function(String) export;
  final String label;
  @override
  State<_ReportExportButton> createState() => _ReportExportButtonState();
}

class _ReportExportButtonState extends State<_ReportExportButton> {
  bool _busy = false;
  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? message;
    try {
      final report = widget.report();
      if (report == null) {
        message = '错误记录已不可用，请从诊断页导出报告';
      } else {
        message = await widget.export(report);
      }
    } on Object {
      message = '报告文件未导出，请重试或复制诊断信息';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && message != null) {
      if (ScaffoldMessenger.maybeOf(context) case final messenger?)
        uiShowFeedbackNotice(messenger, message);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _busy ? null : _export,
    icon: const Icon(Icons.ios_share_outlined, size: 18),
    label: Text(widget.label),
  );
}
