import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/bhpan/view.dart';
import 'support.dart';

void main() {
  testWidgets('同账号服务重建重新取得目录句柄并保留所在路径', (tester) async {
    Future<void> mount(Files service) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BhpanView(
            access: BhpanAccess(service: service),
            scopeKey: 'same-account',
          ),
        ),
      ),
    );
    await mount(Files());
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    final next = _ReboundFiles();
    await mount(next);
    await tester.pumpAndSettle();
    expect(next.reads.map((q) => q.target), [null, 'new-root', 'new-folder']);
    expect(find.text('课程资料'), findsOneWidget);
    expect(find.text('报告.txt'), findsOneWidget);
  });

  testWidgets('校园入口与我的云盘空间指标打开同一云盘服务', (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = Files();
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialDestination: UiDestination.campus,
          bhpanService: files,
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(feature: id, status: FeatureLoadStatus.empty),
          },
          routePolicy: RoutePolicy.direct,
          telemetryEnabled: false,
          activeRoutes: const [ConnectionMode.direct],
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
    await tester.tap(find.text('北航云盘'));
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.me.index),
    );
    await tester.pumpAndSettle();
    final metric = find.byKey(const ValueKey('me-metric-cloud'));
    await tester.ensureVisible(metric);
    await tester.tap(metric);
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsOneWidget);
    expect(
      files.reads.where((q) => q.view == BhpanReadView.personalRoot).length,
      2,
    );
  });
}

class _ReboundFiles extends Files {
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    reads.add(query);
    if (query.view == BhpanReadView.personalRoot)
      return page([
        const BhpanItem(
          handle: 'new-root',
          name: '个人文档库',
          kind: BhpanItemKind.folder,
          scope: BhpanScope.personal,
        ),
      ]);
    if (query.target == 'new-root')
      return page([
        const BhpanItem(
          handle: 'new-folder',
          name: '课程资料',
          kind: BhpanItemKind.folder,
          scope: BhpanScope.personal,
        ),
      ]);
    if (query.target == 'new-folder') return page([file]);
    throw StateError('旧客户端句柄已失效');
  }
}
