import '../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import 'feedback_notice.dart' show uiShowFeedbackNotice;
import 'app_links.dart' show uiShowAppLinkFailure;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 所有错误卡共用本次运行的诊断出口，包括弹窗中的错误卡。
class UiDiagnosticsScope extends InheritedWidget {
  const UiDiagnosticsScope({
    this.exportReport,
    this.exportLabel = '分享诊断报告',
    this.openFeedback,
    required super.child,
    super.key,
  });
  final Future<String?> Function(String report)? exportReport;
  final String exportLabel;
  final Future<bool> Function()? openFeedback;

  static UiDiagnosticsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiDiagnosticsScope>();

  @override
  bool updateShouldNotify(UiDiagnosticsScope oldWidget) =>
      exportReport != oldWidget.exportReport ||
      exportLabel != oldWidget.exportLabel ||
      openFeedback != oldWidget.openFeedback;
}

/// 错误现场只给出编号，反馈统一从「设置 › 诊断信息」分享完整诊断。
const uiDiagnosticsGuidance = '如需反馈，请到「设置 › 诊断信息」分享完整诊断。';

/// 统一错误卡片，避免将上游正文、URL 或堆栈直接展示给用户。
class FriendlyErrorCard extends StatelessWidget {
  const FriendlyErrorCard({
    required this.error,
    this.onRetry,
    this.diagnosticsGuidance = uiDiagnosticsGuidance,
    super.key,
  });

  final UiError error;
  final VoidCallback? onRetry;

  /// 设置页不可达的现场（如登录页）可改为指向就近的诊断入口。
  final String diagnosticsGuidance;

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
                      guidance: diagnosticsGuidance,
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

/// 行内状态与短提示使用同一个错误详情入口。
VoidCallback? uiErrorDetailsAction(BuildContext context, UiError? error) {
  if (error == null || _safeIssueId(error) == null) return null;
  return () {
    if (context.mounted) unawaited(uiShowErrorDetails(context, error));
  };
}

/// 只展示错误编号与代码，并指引到设置中分享完整诊断。
Future<void> uiShowErrorDetails(BuildContext context, UiError error) async {
  final id = _safeIssueId(error);
  if (id == null) return;
  await showUiSheet<void>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return UiSheetBody(
        title: '错误详情',
        subtitle: error.title,
        children: [
          SelectableText('错误编号：$id', style: muted),
          const SizedBox(height: 4),
          SelectableText('错误代码：${error.code.wireName}', style: muted),
          const SizedBox(height: 16),
          const Text(uiDiagnosticsGuidance),
        ],
      );
    },
  );
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

/// 错误编号默认收起；展开后以小字列出，并指引到诊断信息分享。
class _ErrorDetails extends StatefulWidget {
  const _ErrorDetails({
    required this.issueId,
    required this.code,
    required this.guidance,
  });
  final String issueId, code, guidance;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: fg,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            textStyle: theme.textTheme.labelMedium,
          ),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
          label: const Text('错误详情'),
        ),
        if (_open) ...[
          SelectableText('错误编号：${widget.issueId}', style: small),
          SelectableText('错误代码：${widget.code}', style: small),
          const SizedBox(height: 6),
          Text(widget.guidance, style: small),
        ],
      ],
    );
  }
}

/// 诊断信息只提供分享完整诊断，不在界面展示或复制诊断内容。
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

  final scope = UiDiagnosticsScope.of(context);
  await showUiSheet<void>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final muted = theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      );
      return UiSheetBody(
        title: '诊断信息',
        primaryAction: switch (scope?.exportReport) {
          final export? => _ReportExportButton(
            report: readReport,
            export: export,
            label: scope!.exportLabel,
          ),
          null => null,
        },
        children: [
          const Text('遇到问题时，可以把完整诊断发给维护者，帮助定位原因。'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请勿公开分享',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '完整诊断包含学校返回的原始内容，可能有你的姓名、学号、课表等个人信息和登录凭据。'
                        '只私下发给你信任的维护者，不要发到群聊、论坛或 GitHub Issues 等公开场所。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('分享或保存文件不会自动上传，也不会提交反馈。', style: muted),
          if (scope?.openFeedback case final openFeedback?) ...[
            const SizedBox(height: 12),
            Text('反馈页面是公开的，只描述问题现象，不要附上完整诊断。', style: muted),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    unawaited(_openFeedback(context, openFeedback)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开反馈页面'),
              ),
            ),
          ],
          if (scope?.exportReport == null) ...[
            const SizedBox(height: 12),
            Text('当前构建不支持分享诊断。', style: muted),
          ],
        ],
      );
    },
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

/// 一次只打开一个系统面板；失败后可重试。
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
        message = '当前无法读取诊断信息，请稍后重试';
      } else {
        message = await widget.export(report);
      }
    } on Object {
      message = '诊断未能导出，请重试';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && message != null) {
      if (ScaffoldMessenger.maybeOf(context) case final messenger?)
        uiShowFeedbackNotice(messenger, message);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: _busy ? null : _export,
    icon: const Icon(Icons.ios_share_outlined, size: 18),
    label: Text(widget.label),
  );
}
