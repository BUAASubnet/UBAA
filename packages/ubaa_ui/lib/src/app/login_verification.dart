import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../theme.dart' show UbaaTheme;
import 'login_captcha.dart' show CaptchaPixels;

/// 仅在需要人工处理时显示的登录验证窗口。
class UbaaCaptchaDialog extends StatefulWidget {
  const UbaaCaptchaDialog({
    required this.verification,
    required this.isLoading,
    required this.onAnswerChanged,
    required this.onRefresh,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final LoginRouteVerification verification;
  final bool isLoading;
  final ValueChanged<String> onAnswerChanged;
  final VoidCallback onRefresh;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<UbaaCaptchaDialog> createState() => _UbaaCaptchaDialogState();
}

class _UbaaCaptchaDialogState extends State<UbaaCaptchaDialog> {
  late final _answer = TextEditingController(text: widget.verification.answer);

  @override
  void didUpdateWidget(covariant UbaaCaptchaDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_answer.text != widget.verification.answer) {
      _answer.value = TextEditingValue(
        text: widget.verification.answer,
        selection: TextSelection.collapsed(
          offset: widget.verification.answer.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.verification;
    final enabled =
        !widget.isLoading && value.hasUsableFrame && !value.isRefreshing;
    return AlertDialog(
      key: const ValueKey('captcha-dialog'),
      title: const Text('登录验证'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('请输入图片中的验证码，继续完成登录。'),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: '验证码图片，点击刷新',
                child: InkWell(
                  key: ValueKey('captcha-image-${value.route.name}'),
                  onTap: widget.isLoading || value.isRefreshing
                      ? null
                      : widget.onRefresh,
                  borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
                  child: Container(
                    height: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(
                        UbaaTheme.controlRadius,
                      ),
                    ),
                    child: value.isRefreshing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : value.hasUsableFrame
                        ? CaptchaPixels(frame: value.frame!)
                        : const Text('图片暂不可用，点击刷新'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('点击图片刷新', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('captcha-answer-${value.route.name}'),
                controller: _answer,
                enabled: enabled,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                enableInteractiveSelection: false,
                contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: '验证码'),
                onChanged: widget.onAnswerChanged,
                onSubmitted: (_) {
                  if (enabled && _answer.text.trim().isNotEmpty)
                    widget.onSubmit();
                },
              ),
              if (value.error case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('取消')),
        FilledButton(
          key: const ValueKey('captcha-submit'),
          onPressed: enabled && _answer.text.trim().isNotEmpty
              ? widget.onSubmit
              : null,
          child: widget.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('验证'),
        ),
      ],
    );
  }
}
