part of '../widgets.dart';

/// 所有写操作共用的二次确认组件。
///
/// 组件不接收任意 JSON 或原始请求，只接收 bridge 已校验的 [WriteIntent]；
/// 提交按钮在意图过期或提交中自动禁用。
class WriteConfirmationView extends StatefulWidget {
  const WriteConfirmationView({
    required this.intent,
    required this.onCancel,
    required this.onConfirm,
    this.showTitle = true,
    this.showRoute = true,
    this.isSubmitting = false,
    this.isDiscarding = false,
    this.error,
    super.key,
  });

  final bool showTitle;
  final bool showRoute;
  final WriteIntent intent;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;
  final bool isSubmitting;
  final bool isDiscarding;
  final UiError? error;

  @override
  State<WriteConfirmationView> createState() => _WriteConfirmationViewState();
}

class _WriteConfirmationViewState extends State<WriteConfirmationView> {
  Timer? _expiryTimer;
  bool _deadlineReached = false;

  @override
  void initState() {
    super.initState();
    _observeDeadline();
  }

  @override
  void didUpdateWidget(covariant WriteConfirmationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intent.intentId != widget.intent.intentId ||
        oldWidget.intent.expiresAt != widget.intent.expiresAt) {
      _observeDeadline();
    }
  }

  void _observeDeadline() {
    _expiryTimer?.cancel();
    final remaining = widget.intent.expiresAt.difference(DateTime.now());
    _deadlineReached = remaining <= Duration.zero;
    if (!_deadlineReached) {
      // 只更新展示，不延长期限或修改协调器拥有的一次性意图。
      _expiryTimer = Timer(remaining, () {
        if (mounted) setState(() => _deadlineReached = true);
      });
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final expired =
        !widget.isSubmitting && (_deadlineReached || intent.isExpired());
    final showTitle = widget.showTitle;
    final isSubmitting = widget.isSubmitting;
    final isDiscarding = widget.isDiscarding;
    final error = widget.error;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (showTitle)
                  Text(
                    '确认${intent.operation.title}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                if (showTitle) const SizedBox(height: 16),
                _DetailField(label: '目标', value: intent.targetSummary),
                if (widget.showRoute) ...[
                  const SizedBox(height: 8),
                  _DetailField(
                    label: '实际路线',
                    value: intent.resolvedRoute.label,
                  ),
                ],
                const SizedBox(height: 8),
                _DetailField(
                  label: '有效期至',
                  value: _formatDateTime(intent.expiresAt),
                ),
                if (intent.warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text('请注意', style: Theme.of(context).textTheme.titleSmall),
                  for (final warning in intent.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('• $warning'),
                    ),
                ],
                if (error case final error?) ...<Widget>[
                  const SizedBox(height: 16),
                  FriendlyErrorCard(error: error),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: isSubmitting ? null : widget.onCancel,
                      child: isDiscarding
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('正在取消'),
                              ],
                            )
                          : const Text('取消'),
                    ),
                    FilledButton.icon(
                      onPressed: expired || isSubmitting
                          ? null
                          : () => widget.onConfirm(),
                      icon: isSubmitting && !isDiscarding
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(expired ? '意图已过期' : '确认提交'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
