import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/schedule/navigation/backend.dart';

class _EntryBackend extends ScheduleNavigationBackend {
  final terms = Completer<void>(),
      weeks = Completer<void>(),
      courses = Completer<void>();
  final calls = <FeatureQueryView>[];
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.schedule) {
      calls.add(query.view);
      switch (query.view) {
        case FeatureQueryView.scheduleTerms:
          await terms.future;
        case FeatureQueryView.scheduleWeeks:
          await weeks.future;
        case FeatureQueryView.scheduleWeek:
          await courses.future;
        default:
          break;
      }
    }
    return super.loadFeatureQuery(feature, query);
  }
}

void main() {
  testWidgets('首页空课表入口逐帧只显示加载态，索引不闪入正文', (tester) async {
    final backend = _EntryBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天没有课程安排'));
    Future<void> loadingFrames() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(
          find.text('合成本学期'),
          findsNothing,
          reason: '索引仅用于自动定位，不能作为过渡页面显示',
        );
        expect(find.text('合成上一学期'), findsNothing);
        expect(find.text('合成教学第3周'), findsNothing);
        expect(find.text('合成教学第5周'), findsNothing);
        expect(find.text('选择周次'), findsNothing, reason: '自动定位完成前不显示尚不可用的周切换条');
      }
    }

    await loadingFrames();
    backend.terms.complete();
    await loadingFrames();
    backend.weeks.complete();
    await loadingFrames();
    backend.courses.complete();
    await tester.pumpAndSettle();
    expect(find.text('合成课程1'), findsOneWidget);
    expect(find.text('合成教学第4周'), findsOneWidget);
    // 首页后台元数据与课表入口各自读取索引；这里只核对实际课程目标。
    expect(
      backend.calls,
      containsAllInOrder([
        FeatureQueryView.scheduleTerms,
        FeatureQueryView.scheduleWeeks,
        FeatureQueryView.scheduleWeek,
      ]),
    );
    expect(backend.scheduleReads.single.term, '2026-2027-1');
    expect(backend.scheduleReads.single.week, 4);
    final before = backend.calls.length;
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天没有课程安排'));
    await tester.pumpAndSettle();
    expect(find.text('合成课程1'), findsOneWidget);
    expect(backend.calls.length, before);
  });
  testWidgets('自动定位失败可重试，恢复后直接显示课表', (tester) async {
    final backend = _EntryBackend()
      ..failOptions = FeatureQueryView.scheduleWeeks;
    backend.terms.complete();
    backend.weeks.complete();
    backend.courses.complete();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天没有课程安排'));
    await tester.pumpAndSettle();
    expect(backend.scheduleReads, isEmpty);
    backend.failOptions = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('合成课程1'), findsOneWidget);
  });

  testWidgets('自动定位时取消学期选择仍能继续进入课表', (tester) async {
    final backend = _EntryBackend();
    backend.weeks.complete();
    backend.courses.complete();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天没有课程安排'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('选择学期'));
    await tester.pump();
    backend.terms.complete();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('合成课程1'), findsOneWidget);
    expect(backend.scheduleReads.single.week, 4);
  });
}
