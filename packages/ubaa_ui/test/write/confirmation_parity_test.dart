import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('已经提交后跨过准备期限仍显示忙碌而非意图过期', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WriteConfirmationView(
            intent: intent(
              expires: DateTime.now().add(const Duration(seconds: 2)),
            ),
            isSubmitting: true,
            onCancel: () {},
            onConfirm: () async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('确认已过期'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('停留确认页跨过原意图有效期会自动禁用提交且可取消', (tester) async {
    var confirms = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WriteConfirmationView(
            intent: intent(
              expires: DateTime.now().add(const Duration(seconds: 2)),
            ),
            onCancel: () {},
            onConfirm: () async => confirms++,
          ),
        ),
      ),
    );
    expect(find.text('确认提交'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('确认已过期'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(confirms, 0);
  });
}

WriteIntent intent({DateTime? expires}) => WriteIntent(
  intentId: 'synthetic-confirmation',
  operation: WriteOperation.signinPerform,
  targetSummary: '合成课程',
  resolvedRoute: ConnectionMode.direct,
  warnings: const [],
  expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 5)),
  requestDigest: 'synthetic-digest',
);
