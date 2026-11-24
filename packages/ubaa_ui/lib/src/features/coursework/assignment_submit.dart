import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../write_callbacks.dart'
    show
        SpocSubmitFile,
        SpocSubmitFilePicker,
        SpocSubmitInput,
        SpocSubmitStarter;
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/dialogs/confirmation.dart' show uiConfirmIrreversible;

/// 作业详情里的提交入口：资格与目标全部来自 Core 的 typed action。
///
/// 不可提交时只展示 Core 给出的原因，不在本地推断或隐藏成“未开放”。
class SpocSubmitBlock extends StatefulWidget {
  const SpocSubmitBlock({
    super.key,
    required this.action,
    this.title,
    this.reason,
    this.enabled = true,
    this.pickFile,
    this.onSubmit,
  });
  final SpocSubmitAction? action;

  /// 确认弹窗里回指具体作业，避免选完文件就提交、事后才发现交错了。
  final String? title;
  final String? reason;

  /// 整页读取中或已有写入进行时暂停入口，避免准备阶段被顶掉。
  final bool enabled;
  final SpocSubmitFilePicker? pickFile;
  final SpocSubmitStarter? onSubmit;

  @override
  State<SpocSubmitBlock> createState() => _SpocSubmitBlockState();
}

class _SpocSubmitBlockState extends State<SpocSubmitBlock> {
  var _busy = false;

  bool get _canSubmit =>
      widget.action != null &&
      widget.enabled &&
      widget.pickFile != null &&
      widget.onSubmit != null;

  Future<void> _submit() async {
    final action = widget.action;
    final pick = widget.pickFile;
    final start = widget.onSubmit;
    if (action == null || pick == null || start == null || _busy) return;
    SpocSubmitFile? file;
    try {
      file = await pick();
    } on Object catch (error) {
      if (!mounted) return;
      _fail(error);
      return;
    }
    if (file == null || !mounted) return;
    // 选完文件只是选定目标，落盘与提交都在确认之后；取消则一次请求都不发。
    final confirmed = await uiConfirmIrreversible(
      context,
      title: '确认提交这份作业？',
      message: _confirmMessage(file),
      action: '确认提交',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await start(SpocSubmitInput(action: action, file: file));
    } on Object catch (error) {
      if (mounted) _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 确认文案只说上游与本次已知的事：作业名、文件名、能否重复提交。
  String _confirmMessage(SpocSubmitFile file) {
    final lines = <String>[
      if (uiNonBlank(widget.title) case final title?) '作业：$title',
      '文件：${file.name}',
      if (widget.action?.maxSubmissions case final max?)
        max <= 1 ? '这门作业只能提交一次，提交后不可修改。' : '这门作业最多提交 $max 次。',
    ];
    return lines.join('\n');
  }

  void _fail(Object error) {
    // 写入流程本身会展示结果与失败提示；这里只保证界面不残留进行中状态。
    setState(() => _busy = false);
    if (error is UiError) {
      // 选择文件失败没有进入写入流程，需要就地提示。
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final action = widget.action;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    if (action == null)
      return uiNonBlank(widget.reason) == null
          ? const SizedBox.shrink()
          : Text(uiNonBlank(widget.reason)!, style: muted);
    final allowed = action.allowedExtensions
        .map((value) => value.startsWith('.') ? value : '.$value')
        .join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                uiNonBlank(allowed) == null
                    ? '文件提交'
                    : '支持 ${uiNonBlank(allowed)}，单个文件不超过 100 MB',
                style: muted,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _canSubmit && !_busy ? _submit : null,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(_busy ? '正在提交…' : '提交作业'),
            ),
          ],
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('上传与提交完成后会自动核对，请勿关闭页面。', style: muted),
          ),
      ],
    );
  }
}
