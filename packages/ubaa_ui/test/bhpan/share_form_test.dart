import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/bhpan/share_form.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('修改已有分享默认保留原提取码', (tester) async {
    final scope = ValueNotifier(0);
    addTearDown(scope.dispose);
    BhpanShareSettings? result;
    const existing = BhpanShare(
      handle: 'share-1',
      title: '实验资料',
      expiresAt: '1970-01-01T08:00:00+08:00',
      passwordRequired: true,
      limitedTimes: -1,
      permissions: [BhpanPermission.display, BhpanPermission.download],
      canUpdate: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await bhpanShareDialog(
                  context,
                  scope: scope,
                  title: existing.title,
                  existing: existing,
                );
              },
              child: const Text('编辑分享'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑分享'));
    await tester.pumpAndSettle();
    expect(find.text('保留原提取码'), findsOneWidget);
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.keepPassword, isTrue);
    expect(result!.password, isEmpty);
  });
}
