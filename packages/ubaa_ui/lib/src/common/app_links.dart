import '../shared/feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:ubaa_domain/ubaa_domain.dart';

Future<void> uiShowAppLinkFailure(BuildContext context, AppLink link) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('链接未能打开'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可以复制地址后在浏览器中打开。'),
            const SizedBox(height: 12),
            SelectableText(link.url),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: link.url));
                if (context.mounted) Navigator.pop(context);
              } on Object {
                if (context.mounted) {
                  UbaaFeedback.show(
                    context,
                    '复制失败，请重试。',
                    kind: UbaaFeedbackKind.error,
                  );
                }
              }
            },
            child: const Text('复制地址'),
          ),
        ],
      ),
    );
