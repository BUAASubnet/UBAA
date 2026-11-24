import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart' show UbaaFeedback, UbaaFeedbackKind;
import '../../shared/text.dart' show uiNonBlank;
import 'course_files_view.dart' show uiCourseFileIcon, uiFileSize;
import 'spoc_files_access.dart';

/// 作业附件与本人已提交文件：只读取与下载，不发起任何提交。
class SpocAssignmentFiles {
  const SpocAssignmentFiles({
    required this.attachment,
    required this.submittedFile,
    required this.access,
  });
  final SpocAttachment? attachment;
  final SpocSubmittedFile? submittedFile;
  final SpocFilesAccess? access;

  bool get isEmpty => attachment == null && submittedFile == null;

  List<Widget> rows(BuildContext context) => [
    if (attachment case final file?)
      _FileRow(
        key: ValueKey(('assignment-attachment', file.fileId)),
        label: '作业附件',
        file: file,
        meta: [
          if (uiNonBlank(file.sizeText) case final size?) '约 $size',
          if (uiNonBlank(file.extension) case final ext?) ext.toUpperCase(),
        ],
        access: access,
      ),
    if (submittedFile case final file?)
      _FileRow(
        key: ValueKey(('assignment-submission', file.fileId)),
        label: '我的提交',
        file: file,
        meta: const [],
        access: access,
      ),
  ];
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    super.key,
    required this.label,
    required this.file,
    required this.meta,
    required this.access,
  });
  final String label;
  final SpocSubmittedFile file;
  final List<String> meta;
  final SpocFilesAccess? access;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  var _busy = false;

  Future<void> _download() async {
    final download = widget.access?.downloadFile;
    if (download == null || _busy) return;
    setState(() => _busy = true);
    try {
      final receipt = await download(widget.file);
      if (!mounted) return;
      if (receipt != null) {
        UbaaFeedback.show(
          context,
          '已保存 ${receipt.fileName}（${uiFileSize(receipt.byteLen)}）',
          kind: UbaaFeedbackKind.success,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      UbaaFeedback.show(
        context,
        error is UiError ? error.message : '下载失败，请稍后重试',
        error: error is UiError ? error : null,
        kind: UbaaFeedbackKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final name = uiNonBlank(widget.file.fileName) ?? '未命名的文件';
    final canDownload = widget.access?.downloadFile != null;
    final meta = widget.meta;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: canDownload && !_busy ? _download : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              uiCourseFileIcon(switch (widget.file) {
                SpocAttachment file => file.extension,
                _ => null,
              }),
              size: 22,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: muted?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  if (meta.isNotEmpty) Text(meta.join(' · '), style: muted),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (canDownload)
              IconButton(
                tooltip: '下载',
                onPressed: _download,
                icon: const Icon(Icons.download_outlined, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}
