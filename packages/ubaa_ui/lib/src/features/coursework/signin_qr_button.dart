import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart' show SigninPhase;
import '../../common/tag.dart';

class SigninQrButton extends StatelessWidget {
  const SigninQrButton({super.key, required this.phase, this.onOpen});

  final SigninPhase phase;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (phase.isCompleted) {
      const status = UiTag('已签到', tone: UiTagTone.primary);
      if (!phase.canOpenQr || onOpen == null) return status;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          status,
          FilledButton.tonal(onPressed: onOpen, child: const Text('二维码')),
        ],
      );
    }
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: phase == SigninPhase.open ? onOpen : null,
          child: const Text('上课'),
        ),
        if (phase == SigninPhase.upcoming)
          Text(
            '上课前 10 分钟开放',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
