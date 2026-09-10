import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('图书馆沿旧版显示楼馆楼层并使用typed ID进入分区', (tester) async {
    final queries = <FeatureQuery>[];
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          initialTab: 1,
          user: const UserSummary(username: 'synthetic'),
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.success,
                details: id == FeatureId.libbook
                    ? [
                        FeatureDetail(
                          title: '错误展示馆名',
                          fields: const [
                            FeatureField(label: '馆 ID', value: 'wrong'),
                          ],
                          presentation: LibbookLibraryPresentation(
                            id: 'real-library',
                            name: '合成楼馆',
                            queryDate: '2026-09-04',
                            freeNum: 3,
                            totalNum: 40,
                            storeys: const [
                              LibbookStoreyPresentation(
                                id: 'real-floor',
                                name: '一层',
                                freeNum: 3,
                                totalNum: 20,
                              ),
                            ],
                          ),
                        ),
                      ]
                    : const [],
              ),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (_, query) async {
            queries.add(query);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.libbook);
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('libbook-choice-楼馆')),
          )
          .value,
      'real-library',
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('libbook-choice-楼层')),
          )
          .value,
      'real-floor',
    );
    expect(queries, hasLength(1));
    expect(queries.single.view, FeatureQueryView.libbookAreas);
    expect(queries.single.premisesId, 'real-library');
    expect(queries.single.storeyId, 'real-floor');
    expect(queries.single.date, DateTime(2026, 9, 4));
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
