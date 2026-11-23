import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';

const _qr = 'https://example.invalid/signin';
final _sheet = find.byType(SigninQrSheet);
final _retry = find.widgetWithIcon(FilledButton, Icons.refresh_rounded);
final _save = find.widgetWithIcon(FilledButton, Icons.download_rounded);
final _success = find.byIcon(Icons.check_circle_outline_rounded);
final _failure = find.byIcon(Icons.error_outline_rounded);

void main() {
  testWidgets('二维码立即获取并每两秒以零偏移刷新，后台暂停', (tester) async {
    final offsets = <Duration>[];
    await _open(
      tester,
      fetch: (offset) async {
        offsets.add(offset);
        return _qr;
      },
    );
    expect(offsets, [Duration.zero]);
    await tester.pump(const Duration(seconds: 1));
    expect(offsets, [Duration.zero]);
    await tester.pump(const Duration(seconds: 1));
    expect(offsets, [Duration.zero, Duration.zero]);
    _hide(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(offsets, [Duration.zero, Duration.zero]);
    _resume(tester);
    await tester.pump();
    expect(offsets, [Duration.zero, Duration.zero, Duration.zero]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('取码失败后暂停刷新，状态检查继续，手动重取恢复刷新', (tester) async {
    var fetches = 0;
    var checks = 0;
    await _open(
      tester,
      fetch: (_) async {
        if (++fetches == 1) throw StateError('取码失败');
        return _qr;
      },
      check: () async {
        checks++;
        return false;
      },
    );
    expect(_retry, findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    expect(fetches, 1);
    expect(checks, greaterThan(0));
    await tester.tap(_retry);
    await tester.pump();
    expect(fetches, 2);
    expect(_retry, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(fetches, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('在途二维码请求切到后台后失败，上课状态查询次数保持为零', (tester) async {
    final request = Completer<String>();
    var checks = 0;
    await _open(
      tester,
      fetch: (_) => request.future,
      check: () async {
        checks++;
        return false;
      },
      settle: false,
    );
    _hide(tester);
    request.completeError(StateError('后台取码失败'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(checks, 0);
    _resume(tester);
    await tester.pump();
    expect(checks, 1);
    expect(_retry, findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    expect(checks, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('上课检查失败后继续，查询防重入，已上课关闭并停止计时', (tester) async {
    final pending = Completer<bool>();
    var checks = 0;
    var fetches = 0;
    await _open(
      tester,
      fetch: (_) async {
        fetches++;
        return _qr;
      },
      check: () async {
        if (++checks == 1) throw StateError('查询失败');
        return pending.future;
      },
    );
    await tester.pump(const Duration(seconds: 2));
    expect(checks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(checks, 1);
    expect(_sheet, findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    expect(checks, 2);
    _hide(tester);
    await tester.pump(const Duration(seconds: 6));
    _resume(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(checks, 2);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    final fetchesAtClose = fetches;
    await tester.pump(const Duration(seconds: 6));
    expect(checks, 2);
    expect(fetches, fetchesAtClose);
  });

  for (final (platform, saved) in [
    (TargetPlatform.android, true),
    (TargetPlatform.macOS, true),
    (TargetPlatform.macOS, false),
    (TargetPlatform.macOS, null),
  ]) {
    testWidgets('$platform 保存结果为 ${saved ?? '异常'}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final offsets = <Duration>[];
      final png = Uint8List.fromList([1, 2, 3]);
      await _open(
        tester,
        fetch: (offset) async {
          offsets.add(offset);
          return offset == Duration.zero ? _qr : '保存用二维码';
        },
        renderPng: (content) async {
          expect(content, '保存用二维码');
          return png;
        },
        save: (bytes, name) async {
          expect(bytes, same(png));
          expect(name, 'iclass_signin_qr.png');
          if (saved == null) throw StateError('保存失败');
          return saved;
        },
      );
      await tester.tap(_save);
      await tester.pump();
      expect(offsets, [Duration.zero, const Duration(seconds: 2)]);
      if (saved == true) {
        expect(_success, findsWidgets);
      } else if (saved == null) {
        expect(_failure, findsWidgets);
      } else {
        expect(_success, findsNothing);
        expect(_failure, findsNothing);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(_success, findsNothing);
      expect(_failure, findsNothing);
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('默认编码把 PNG 交给平台保存回调', (tester) async {
    Completer<Uint8List>? savedPng;
    await _open(
      tester,
      fetch: (_) async => _qr,
      save: (png, _) async {
        savedPng!.complete(png);
        return false;
      },
    );
    final bytes = await tester.runAsync(() async {
      savedPng = Completer<Uint8List>();
      await tester.tap(_save);
      return savedPng!.future.timeout(const Duration(seconds: 5));
    });
    expect(bytes?.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('没有平台保存回调时不提供保存操作', (tester) async {
    await _open(tester, fetch: (_) async => _qr);
    expect(_save, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _open(
  WidgetTester tester, {
  required SigninQrContentFetcher fetch,
  SigninQrImageSaver? save,
  SigninSignedChecker? check,
  bool settle = true,
  Future<Uint8List> Function(String)? renderPng,
}) async {
  _resume(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              if (renderPng == null) {
                showSigninQrSheet(
                  context,
                  courseTitle: '合成课程',
                  fetch: fetch,
                  save: save,
                  closeWhenSigned: check,
                );
              } else {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SigninQrSheet(
                    courseTitle: '合成课程',
                    fetch: fetch,
                    save: save,
                    closeWhenSigned: check,
                    renderPng: renderPng,
                  ),
                );
              }
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextButton));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void _hide(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
