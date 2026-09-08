import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产考试与课堂签到只读；只输出状态计数，不截图或准备签到。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产考试三视图与签到旧布局双路线只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-') ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式提供生产只读开关、隔离配置和预期路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 480 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '生产只读状态未在限定时间完成');
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    UbaaMainShell shell() =>
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    Future<void> tap(Finder finder) async {
      expect(finder.evaluate().isNotEmpty, isTrue, reason: '只读入口未出现');
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> loaded(FeatureId id, FeatureQueryView view) async {
      await waitFor(() {
        final value = shell().snapshots[id]!;
        return (view == FeatureQueryView.summary
                ? (value.readContext != null &&
                      (value.readContext?.query == null ||
                          value.readContext?.query?.view == view))
                : value.readContext?.query?.view == view) &&
            value.status != FeatureLoadStatus.idle &&
            value.status != FeatureLoadStatus.loading;
      });
      final value = shell().snapshots[id]!;
      debugPrint(
        '学业旧版只读 feature=${id.name} view=${view.name} status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(value.resolvedRoute?.name, route);
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> open(FeatureId feature, IconData group) async {
      await tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(group),
        ),
      );
      await tap(find.widgetWithText(Card, feature.title));
      await loaded(feature, FeatureQueryView.summary);
      expect(find.byType(TextField).evaluate().isEmpty, isTrue);
      expect(
        find
            .byTooltip(route == 'direct' ? '实际路线：直连' : '实际路线：WebVPN')
            .evaluate()
            .isNotEmpty,
        isTrue,
      );
    }

    await open(FeatureId.exam, Icons.apps_outlined);
    for (final (label, view) in [
      ('已安排', FeatureQueryView.examArranged),
      ('未安排', FeatureQueryView.examNotArranged),
      ('全部考试', FeatureQueryView.summary),
    ]) {
      await tap(find.byTooltip('搜索与筛选'));
      await tap(find.byType(DropdownButton<FeatureQueryView>));
      await tap(find.text(label).last);
      final revision =
          shell().snapshots[FeatureId.exam]!.readContext?.requestRevision;
      await tap(find.text('应用筛选'));
      await waitFor(
        () =>
            shell().snapshots[FeatureId.exam]!.readContext?.requestRevision !=
            revision,
      );
      await loaded(FeatureId.exam, view);
      await tap(find.widgetWithText(TextButton, '完成'));
      expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    }
    debugPrint(
      '学业旧版只读 examLocalDetail=${shell().snapshots[FeatureId.exam]!.details.isEmpty ? '无记录未执行' : '本批未执行'}',
    );
    await tap(find.byTooltip('返回'));
    await open(FeatureId.signin, Icons.auto_awesome_outlined);
    if (shell().snapshots[FeatureId.signin]!.details.isNotEmpty) {
      final revision =
          shell().snapshots[FeatureId.signin]!.readContext?.requestRevision;
      await tap(find.byTooltip('课程详情').first);
      expect(find.byType(AlertDialog).evaluate().isNotEmpty, isTrue);
      await tap(find.widgetWithText(TextButton, '关闭'));
      expect(
        shell().snapshots[FeatureId.signin]!.readContext?.requestRevision,
        revision,
      );
      debugPrint('学业旧版只读 signinLocalDetail=true extraRead=false');
    } else {
      debugPrint('学业旧版只读 signinLocalDetail=无记录未执行');
    }
    expect(
      MaterialLocalizations.of(
        tester.element(find.byType(UbaaMainShell)),
      ).openAppDrawerTooltip,
      '打开导航菜单',
    );
    debugPrint('学业旧版只读 完成 businessWrites=0');
  });
}
