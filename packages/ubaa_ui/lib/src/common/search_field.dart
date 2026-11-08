import 'package:flutter/material.dart';

/// 全应用统一的搜索框：48 高填充胶囊、无描边，左侧放大镜，有内容时右侧显示清除。
///
/// 功能列表、iHome、日程和云盘共用，旁边的图标按钮使用 [UiSearchField.height] 对齐。
class UiSearchField extends StatelessWidget {
  const UiSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.enabled = true,
    this.maxLength,
    this.clearTooltip = '清除搜索',
    this.fieldKey,
  });

  static const double height = 48;

  final TextEditingController controller;
  final String hintText;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 为空时清除按钮只清空文字并回调 [onChanged]。
  final VoidCallback? onClear;
  final bool enabled;
  final int? maxLength;
  final String clearTooltip;

  /// 放在内部输入框上的 key，供既有入口按输入框定位。
  final Key? fieldKey;

  void _clear() {
    if (onClear case final clear?) {
      clear();
      return;
    }
    controller.clear();
    onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        maxLength: maxLength,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: (text) {
          onSubmitted?.call(text);
          FocusManager.instance.primaryFocus?.unfocus();
        },
        decoration: InputDecoration(
          hintText: hintText,
          counterText: '',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: clearTooltip,
                  onPressed: enabled ? _clear : null,
                  icon: const Icon(Icons.close),
                ),
          constraints: const BoxConstraints(minHeight: height),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(height / 2)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
