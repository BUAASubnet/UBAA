import '../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import '../shared/feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ubaa_domain/ubaa_domain.dart';

Future<void> uiShowAppLinkFailure(BuildContext context, AppLink link) =>
    showUiSheet<void>(
      context,
      builder: (context) => UiSheetBody(
        title: '链接未能打开',
        subtitle: '可以复制地址后在浏览器中打开。',
        children: [SelectableText(link.url)],
        primaryAction: FilledButton.icon(
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: link.url));
              if (context.mounted) Navigator.pop(context);
            } on Object {
              if (context.mounted) {
                UbaaFeedback.show(
                  context,
                  '复制失败，请重试',
                  kind: UbaaFeedbackKind.error,
                );
              }
            }
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('复制地址'),
        ),
      ),
    );
