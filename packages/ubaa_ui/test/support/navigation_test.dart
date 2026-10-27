import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation.dart';

void main() {
  testWidgets('没有可点击筛选入口时立即失败，不能静默跳过交互', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    await expectLater(openQueryPanel(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('隐藏的筛选入口不能当作可操作入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Offstage(
            child: IconButton(
              key: const ValueKey<String>('feature-filter-button'),
              tooltip: '筛选',
              onPressed: () {},
              icon: const Icon(Icons.tune),
            ),
          ),
        ),
      ),
    );

    await expectLater(openQueryPanel(tester), throwsA(isA<TestFailure>()));
  });
}
