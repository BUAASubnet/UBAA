import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/error_card.dart' show FriendlyErrorCard;
import '../../shared/dialogs/sheet.dart';
import '../../shared/loading.dart';
import '../../common/tag.dart';
import '../../common/state_panel.dart';

class AcademicTermDialog extends StatefulWidget {
  const AcademicTermDialog({required this.loader, required this.selected});
  final Future<FeatureResult> Function(bool forceRefresh) loader;
  final String selected;
  @override
  State<AcademicTermDialog> createState() => _AcademicTermDialogState();
}

class _AcademicTermDialogState extends State<AcademicTermDialog> {
  late Future<FeatureResult> _result;
  @override
  void initState() {
    super.initState();
    _result = widget.loader(false);
  }

  void _reload() {
    final next = widget.loader(true);
    setState(() {
      _result = next;
    });
  }

  /// 由 showUiSheet 打开的底部选择面板。
  @override
  Widget build(BuildContext context) => UiSheetBody(
    title: '选择学期',
    // 重新获取是低频操作，放在标题右侧；底部面板下滑或点遮罩即可关闭，不再放「取消」。
    headerActions: [
      IconButton(
        tooltip: '重新获取',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    children: [
      FutureBuilder<FeatureResult>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 64,
              child: Center(child: LoadingGlyph(dimension: 32)),
            );
          }
          final result = snapshot.data;
          if (result?.error case final error?) {
            return FriendlyErrorCard(error: error, onRetry: _reload);
          }
          if (snapshot.hasError || result == null) {
            return UiStatePanel(
              compact: true,
              icon: Icons.cloud_off_outlined,
              title: '学期读取失败',
              detail: '可以重试，或关闭后手动填写学期编码',
              action: '重试',
              onAction: _reload,
            );
          }
          final terms = <String, FeatureDetail>{};
          for (final detail in result.details) {
            if (detail.presentation case final TermPresentation term
                when term.code.trim().isNotEmpty) {
              terms.putIfAbsent(term.code, () => detail);
            }
          }
          if (terms.isEmpty)
            return const UiStatePanel(
              compact: true,
              icon: Icons.event_busy_outlined,
              title: '暂无可选学期',
              detail: '可关闭后手动填写学期编码',
            );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in terms.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(entry.value.title),
                      // 与选周面板的“本周”同一标签样式。
                      if ((entry.value.presentation! as TermPresentation)
                          .selected)
                        const UiTag('当前学期', tone: UiTagTone.primary),
                    ],
                  ),
                  selected: entry.key == widget.selected,
                  trailing: entry.key == widget.selected
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(entry.key),
                ),
            ],
          );
        },
      ),
    ],
  );
}
