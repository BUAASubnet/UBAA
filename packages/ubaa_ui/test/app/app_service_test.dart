import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/app_service/notices.dart';
import 'package:ubaa_ui/src/app/app_service/privacy.dart';
import 'package:ubaa_ui/src/app/app_service/settings.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const _policy = PrivacyPolicyDocument(
  version: 2,
  title: '隐私政策',
  blocks: [
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '合成章节',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '合成段落',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '合成条目',
    ),
  ],
  changes: ['合成变更要点'],
);

AppServiceView _view({
  AppServiceConsent consent = AppServiceConsent.agreed,
  bool telemetryAllowed = true,
  bool telemetryEnabled = true,
  bool canErase = true,
  AppServiceEraseStatus erase = AppServiceEraseStatus.idle,
}) => AppServiceView(
  available: true,
  telemetryAllowed: telemetryAllowed,
  consent: consent,
  policyVersion: _policy.version,
  agreedPolicyVersion: consent == AppServiceConsent.agreed ? 2 : null,
  telemetryEnabled: telemetryEnabled,
  canErase: canErase,
  erase: erase,
);

/// 记录设置页发出的操作；各操作的结果由测试指定。
class _Calls {
  final log = <String>[];
  Object? failure;
  AppServiceEraseOutcome eraseOutcome = AppServiceEraseOutcome.succeeded;

  Future<void> _record(String name) async {
    log.add(name);
    if (failure case final error?) throw error;
  }

  AppServiceControls controls(AppServiceView view) => AppServiceControls(
    view: view,
    policy: _policy,
    onAgree: () => _record('agree'),
    onDecline: () => _record('decline'),
    onWithdraw: () => _record('withdraw'),
    onTelemetryChanged: (value) => _record('telemetry:$value'),
    onErase: () async {
      log.add('erase');
      return eraseOutcome;
    },
  );
}

Future<void> _mountSettings(WidgetTester tester, AppServiceControls controls) =>
    tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Card(child: AppServiceSettings(controls: controls)),
          ),
        ),
      ),
    );

Future<void> _pushConsent(
  WidgetTester tester, {
  required AppServiceView view,
  required Future<void> Function() onAgree,
  required Future<void> Function() onDecline,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      navigatorKey: navigator,
      home: const Scaffold(body: Text('首页内容')),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      uiPrivacyConsentRoute(
        navigator.currentContext!,
        policy: _policy,
        view: view,
        onAgree: onAgree,
        onDecline: onDecline,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('隐私选择弹窗', () {
    testWidgets('未作选择时返回键和点击外部都不能关闭', (tester) async {
      await _pushConsent(
        tester,
        view: _view(consent: AppServiceConsent.unasked),
        onAgree: () async {},
        onDecline: () async {},
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue, reason: '弹窗拦截返回，不能退回到未作选择的应用');
      expect(find.byType(PrivacyConsentDialog), findsOneWidget);
    });

    testWidgets('同意后保存完成才关闭，保存失败时留在弹窗可重选', (tester) async {
      var attempts = 0;
      final pending = Completer<void>();
      await _pushConsent(
        tester,
        view: _view(consent: AppServiceConsent.unasked),
        onAgree: () {
          attempts++;
          return attempts == 1
              ? Future<void>.error(StateError('合成保存失败'))
              : pending.future;
        },
        onDecline: () async => fail('不应进入基础模式'),
      );
      await tester.tap(find.byKey(const ValueKey('privacy-consent-agree')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyConsentDialog), findsOneWidget);
      expect(find.text('选择未能保存，请重试'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('privacy-consent-agree')));
      await tester.pump();
      final agree = tester.widget<FilledButton>(
        find.byKey(const ValueKey('privacy-consent-agree')),
      );
      expect(agree.onPressed, isNull, reason: '保存期间不能重复提交');
      pending.complete();
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(PrivacyConsentDialog), findsNothing);
      expect(find.text('首页内容'), findsOneWidget);
    });

    testWidgets('不同意进入基础模式并关闭弹窗', (tester) async {
      var declined = false;
      await _pushConsent(
        tester,
        view: _view(consent: AppServiceConsent.unasked),
        onAgree: () async => fail('不应同意'),
        onDecline: () async => declined = true,
      );
      await tester.tap(find.byKey(const ValueKey('privacy-consent-decline')));
      await tester.pumpAndSettle();
      expect(declined, isTrue);
      expect(find.byType(PrivacyConsentDialog), findsNothing);
    });

    testWidgets('政策更新时列出变更要点并说明保留的统计开关', (tester) async {
      await _pushConsent(
        tester,
        view: _view(
          consent: AppServiceConsent.reconsentRequired,
          telemetryEnabled: false,
        ),
        onAgree: () async {},
        onDecline: () async {},
      );
      expect(find.text('合成变更要点'), findsOneWidget);
      expect(find.textContaining('目前为关闭，同意后仍然关闭'), findsOneWidget);
    });

    testWidgets('从弹窗查看离线政策全文后回到选择', (tester) async {
      await _pushConsent(
        tester,
        view: _view(consent: AppServiceConsent.unasked),
        onAgree: () async {},
        onDecline: () async {},
      );
      await tester.tap(
        find.byKey(const ValueKey('privacy-consent-read-policy')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
      expect(find.text('合成章节'), findsOneWidget);
      expect(find.text('合成条目'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyPage), findsNothing);
      expect(find.byType(PrivacyConsentDialog), findsOneWidget);
    });
  });

  group('设置页应用服务条目', () {
    testWidgets('基础模式和硬关闭时开关显示为关闭且不可操作', (tester) async {
      final calls = _Calls();
      for (final view in [
        _view(consent: AppServiceConsent.basic),
        _view(telemetryAllowed: false),
      ]) {
        await _mountSettings(tester, calls.controls(view));
        final tile = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('settings-product-telemetry')),
        );
        expect(tile.value, isFalse, reason: '保存值为开启也不能误报统计正在进行');
        expect(tile.onChanged, isNull);
      }
      expect(calls.log, isEmpty);
    });

    testWidgets('关闭统计失败时提示重试', (tester) async {
      final calls = _Calls()..failure = StateError('合成保存失败');
      await _mountSettings(tester, calls.controls(_view()));
      await tester.tap(
        find.byKey(const ValueKey('settings-product-telemetry')),
      );
      await tester.pumpAndSettle();
      expect(calls.log, ['telemetry:false']);
      expect(find.text('统计设置未能保存，请重试'), findsOneWidget);
    });

    testWidgets('撤回同意先确认，取消时不改变状态', (tester) async {
      final calls = _Calls();
      await _mountSettings(tester, calls.controls(_view()));
      await tester.tap(find.byKey(const ValueKey('settings-privacy-withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.log, isEmpty);

      await tester.tap(find.byKey(const ValueKey('settings-privacy-withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '撤回'));
      await tester.pumpAndSettle();
      expect(calls.log, ['withdraw']);
    });

    testWidgets('基础模式可以从设置页重新打开同意弹窗', (tester) async {
      final calls = _Calls();
      await _mountSettings(
        tester,
        calls.controls(_view(consent: AppServiceConsent.basic)),
      );
      await tester.tap(find.byKey(const ValueKey('settings-privacy-agree')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-consent-agree')));
      await tester.pumpAndSettle();
      expect(calls.log, ['agree']);
      expect(find.byType(PrivacyConsentDialog), findsNothing);
    });

    testWidgets('删除需要确认，结果未知时说明会自动重试', (tester) async {
      final calls = _Calls()..eraseOutcome = AppServiceEraseOutcome.pending;
      await _mountSettings(tester, calls.controls(_view()));
      await tester.tap(find.byKey(const ValueKey('settings-erase-telemetry')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(calls.log, ['erase']);
      expect(find.text('暂时无法连接统计服务，删除会在稍后自动重试'), findsOneWidget);
    });

    testWidgets('删除未完成时点按直接重试，删除进行中不能重复提交', (tester) async {
      final calls = _Calls();
      await _mountSettings(
        tester,
        calls.controls(_view(erase: AppServiceEraseStatus.pending)),
      );
      await tester.tap(find.byKey(const ValueKey('settings-erase-telemetry')));
      await tester.pumpAndSettle();
      expect(calls.log, ['erase']);
      expect(find.text('已删除已上传的统计数据'), findsOneWidget);

      await _mountSettings(
        tester,
        calls.controls(_view(erase: AppServiceEraseStatus.running)),
      );
      // 进度指示一直转动，只推进有限时间。
      await tester.tap(find.byKey(const ValueKey('settings-erase-telemetry')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls.log, ['erase']);
    });
  });

  group('首页更新与公告提示', () {
    final url = Uri.parse('https://example.invalid/update');
    AppUpdateView update({
      AppUpdateStatus status = AppUpdateStatus.updateAvailable,
      bool gate = false,
      bool dismissed = false,
    }) => AppUpdateView(
      status: status,
      latestVersion: '2.1.0+16',
      minSupportedVersion: gate ? '2.1.0' : null,
      url: url,
      releaseNotes: '合成更新说明',
      gateActive: gate,
      availableDismissed: dismissed,
    );

    Future<List<String>> mountNotices(
      WidgetTester tester,
      AppUpdateView? view,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: Scaffold(
            body: AppServiceNoticeList(
              notices: AppServiceNotices(
                update: view,
                onOpenUrl: (url) async => log.add('open:$url'),
                onDismissUpdate: () async => log.add('dismiss'),
                onDismissAnnouncement: (id) async => log.add('read:$id'),
              ),
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('新版本提示可查看说明后前往更新，也可忽略', (tester) async {
      final log = await mountNotices(tester, update());
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.text('合成更新说明'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '前往更新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('忽略'));
      await tester.pumpAndSettle();
      expect(log, ['open:$url', 'dismiss']);
    });

    test('已忽略的新版本、已是最新或服务未给判断时没有首页提示', () {
      for (final view in [
        update(dismissed: true),
        update(status: AppUpdateStatus.upToDate),
        update(status: AppUpdateStatus.unknown),
        null,
      ]) {
        final notices = AppServiceNotices(
          update: view,
          onOpenUrl: (_) async {},
          onDismissUpdate: () async {},
          onDismissAnnouncement: (_) async {},
        );
        expect(notices.isEmpty, isTrue, reason: '$view');
      }
    });

    testWidgets('门控生效时只显示更新要求，服务未给判断也保持', (tester) async {
      final log = await mountNotices(
        tester,
        update(status: AppUpdateStatus.unknown, gate: true),
      );
      expect(
        find.byKey(const ValueKey('home-update-required')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-update-available')), findsNothing);
      await tester.tap(find.text('前往更新'));
      await tester.pumpAndSettle();
      expect(log, ['open:$url']);
    });

    testWidgets('更新提示弹窗返回与前往更新分别给出结果', (tester) async {
      final results = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await uiShowUpdateRequired(context)),
              child: const Text('合成学校操作'),
            ),
          ),
        ),
      );
      for (final choice in ['返回', '前往更新']) {
        await tester.tap(find.text('合成学校操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
      }
      expect(results, [false, true]);
    });
  });
}
