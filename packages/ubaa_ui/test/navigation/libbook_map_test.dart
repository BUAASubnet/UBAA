import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('图书馆地图只按typed分区ID打开静态资源，缩放重置不请求业务', (tester) async {
    await _open(tester, '8');
    await tester.ensureVisible(find.text('查看座位分布'));
    await tester.tap(find.text('查看座位分布'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/libbook_maps/area_8.png',
    );
    expect((image.image as AssetImage).package, 'ubaa_ui');
    expect(find.textContaining('颜色不代表当前可用状态'), findsOneWidget);
    await tester.tap(find.byTooltip('放大'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(controller.value.getTranslation().x, 0);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
  testWidgets('未知分区不能从伪展示编号借用另一张地图', (tester) async {
    await _open(tester, '999');
    expect(find.text('当前分区暂无平面图'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '查看座位分布'),
    );
    expect(button.onPressed, isNull);
  });
}

Future<void> _open(WidgetTester tester, String id) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: UbaaMainShell(
        initialTab: 1,
        user: const UserSummary(username: 'synthetic'),
        snapshots: {
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(
              feature: feature,
              status: FeatureLoadStatus.success,
              readContext: feature == FeatureId.libbook
                  ? FeatureReadContext(
                      requestRevision: 1,
                      query: FeatureQuery(
                        view: FeatureQueryView.libbookAreaDetail,
                        areaId: id,
                      ),
                    )
                  : null,
              details: feature == FeatureId.libbook
                  ? [
                      FeatureDetail(
                        title: '合成分区',
                        fields: const [
                          FeatureField(label: '分区 ID', value: '8'),
                        ],
                        presentation: LibbookAreaDetailPresentation(
                          id: id,
                          name: '合成分区',
                          availableDates: const [],
                          timeSlots: const [],
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
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.libbook);
}
