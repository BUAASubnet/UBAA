import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/home/backend.dart';
import '../../support/home/scroll.dart';

void main() {
  testWidgets('首页恢复六来源并按旧今日课程时间排序，点击待办直达原作业', (tester) async {
    final backend = HomeBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    for (final title in [
      '合成签到待办',
      '合成博雅待办',
      '合成SPOC待办',
      '合成希冀待办',
      '合成研讨室待办',
      '本周阳光打卡未达标',
    ]) {
      await ensureHomeTodo(tester, find.text(title));
      expect(find.text(title), findsOneWidget);
    }
    // 恢复外层首页位置；待办预览、展开和主滚动由窗口专项用例覆盖。
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('合成上午课程')).dy,
      lessThan(tester.getTopLeft(find.text('合成下午课程')).dy),
    );
    await ensureHomeTodo(tester, find.text('合成SPOC待办'));
    // ensureVisible 的默认顶端对齐可能仍落在滚动裁剪区外；点击前居中验证可命中。
    await Scrollable.ensureVisible(
      tester.element(find.text('合成SPOC待办')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(find.text('合成SPOC待办').hitTestable(), findsOneWidget);
    await tester.tap(find.text('合成SPOC待办'));
    await tester.pumpAndSettle();
    expect(backend.homeQueries.last.$2.view, FeatureQueryView.spocDetail);
    expect(backend.homeQueries.last.$2.assignmentId, 'spoc-a');
    final requestsBeforeBack = backend.homeQueries.length;
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text(FeatureId.spoc.title), findsOneWidget);
    expect(backend.homeQueries.length, requestsBeforeBack);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsNothing);
    expect(find.text('合成SPOC待办'), findsOneWidget);
    // 恢复外层首页位置；待办预览、展开和主滚动由窗口专项用例覆盖。
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('合成上午课程'), findsOneWidget);
    expect(find.text('合成下午课程'), findsOneWidget);
    expect(backend.commitCalls, 0);
  });
  testWidgets('首页课堂签到使用原typed目标直接提交，未知结果保留待办且阳光提醒可关闭', (tester) async {
    final backend = HomeBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await ensureHomeTodo(tester, find.widgetWithText(FilledButton, '签到'));
    await tester.tap(find.widgetWithText(FilledButton, '签到'));
    await tester.pumpAndSettle();
    expect(backend.preparedSignin, ['signin-target']);
    expect(backend.commitCalls, 1);
    expect(find.text('合成签到待办'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(backend.commitCalls, 1);
    await ensureHomeTodo(tester, find.text('本周阳光打卡未达标'));
    await tester.tap(find.text('本周阳光打卡未达标'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, '首页提醒'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, '首页提醒'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '首页提醒'))
          .value,
      isFalse,
    );
    final count = backend.homeQueries.length;
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('本周阳光打卡未达标'), findsNothing);
    expect(backend.homeQueries, hasLength(count));
  });
}
