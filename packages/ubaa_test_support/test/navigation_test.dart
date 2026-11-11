import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/navigation.dart';

void main() {
  testWidgets('分类图标与内容快捷入口相同时只点击导航栏', (tester) async {
    var index = 0, wrong = 0, opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, update) => Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.school),
                  onPressed: () => wrong++,
                ),
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) => update(() => index = value),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('首页'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.school_outlined),
                      selectedIcon: Icon(Icons.school),
                      label: Text('学习'),
                    ),
                  ],
                ),
                Expanded(
                  child: index == 1
                      ? Card(
                          child: InkWell(
                            onTap: () => opened++,
                            child: Text(FeatureId.schedule.title),
                          ),
                        )
                      : const Text('首页正文'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await openFeature(tester, FeatureId.schedule);
    expect(index, 1);
    expect(opened, 1);
    expect(wrong, 0);
  });
}
