import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产当前学期只读与独立本地基线；不截图、不输出课程身份或分数。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产首页成绩首次基线与宿主重建只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const expected = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-e2b-') ||
        !{'direct', 'webvpn'}.contains(expected)) {
      throw StateError('必须显式提供本批独立只读配置与预期路线');
    }
    final file = File('$config/ui-grade-scores.json');
    expect(await file.exists(), isFalse, reason: '仅使用本批新的私有基线文件');
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 600 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '生产只读未在限定时间完成');
    }

    UbaaMainShell shell() =>
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    Future<void> loaded() async {
      await waitFor(
        () =>
            find.byType(UbaaMainShell).evaluate().isNotEmpty ||
            find.byType(UbaaLoginView).evaluate().isNotEmpty,
      );
      expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
      await shell().onRetryFeature(FeatureId.grades);
      await waitFor(
        () => {
          FeatureLoadStatus.success,
          FeatureLoadStatus.empty,
          FeatureLoadStatus.failure,
          FeatureLoadStatus.stale,
        }.contains(shell().snapshots[FeatureId.grades]!.status),
      );
      final value = shell().snapshots[FeatureId.grades]!;
      debugPrint(
        '成绩提醒只读 status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(value.resolvedRoute?.name, expected);
      await shell().onCheckGradeUpdates!();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tester.pumpWidget(app!);
    await loaded();
    final route = ConnectionMode.values.singleWhere((r) => r.name == expected);
    final accounts = (app! as UbaaFlutterApp).localAccountStore!;
    Future<GradeScoreBaseline?> readBaseline() async {
      final local = (await accounts.read())!.account!;
      final key = await accounts.cacheKey(local);
      late BridgeOfflineCache cache;
      try {
        cache = await BridgeOfflineCache.open(
          configDir: config,
          accountId: local.id,
          expectedIdentity: local.username,
          key: key,
        );
      } finally {
        key.fillRange(0, key.length, 0);
      }
      try {
        final source = route == ConnectionMode.direct
            ? BridgeConnectionMode.direct
            : BridgeConnectionMode.webVpn;
        final terms = await cache.readAcademicTerms(route: source);
        final current = terms!.data.singleWhere((term) => term.selected);
        final value = await cache.readGradeScoreBaseline(
          route: source,
          term: current.itemCode,
        );
        return value == null
            ? null
            : GradeScoreBaseline(
                termCode: value.termCode,
                termName: value.termName,
                scores: value.scores
                    .map(
                      (v) => GradeScoreEntry(
                        key: v.key,
                        courseName: v.courseName,
                        courseCode: v.courseCode,
                        score: v.score,
                      ),
                    )
                    .toList(),
              );
      } finally {
        cache.dispose();
      }
    }

    final first = await readBaseline();
    expect(
      first != null && first.scores.isNotEmpty,
      isTrue,
      reason: '唯一当前学期的有效基线未建立',
    );
    expect(shell().gradeScoreNotice == null, isTrue);
    expect(shell().gradeCheckRoute?.name, expected);
    expect(await file.exists(), isFalse, reason: '新的真实成绩不创建明文基线');
    debugPrint(
      '成绩提醒只读 firstBaseline=true firstNotice=false encrypted=true entries=${first!.scores.length}',
    );
    // 仅重读当前成绩，不操作任何学校业务写入。
    await shell().onRetryFeature(FeatureId.grades);
    await loaded();
    final beforeRestart = await readBaseline();
    expect(beforeRestart != null, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(app!);
    await loaded();
    final afterRestart = await readBaseline();
    expect(afterRestart != null, isTrue);
    expect(await file.exists(), isFalse);
    final observed =
        afterRestart!.compareWith(beforeRestart, route)?.changes.length ?? 0;
    expect(shell().gradeScoreNotice?.changes.length ?? 0, observed);
    debugPrint(
      '成绩提醒只读 restoredBaseline=true observedChanges=$observed entries=${afterRestart.scores.length} businessWrites=0 完成',
    );
  });
}
