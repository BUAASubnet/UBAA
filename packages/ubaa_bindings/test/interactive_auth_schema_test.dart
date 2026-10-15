import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  final source = File(
    'lib/src/rust/api/interactive_auth.dart',
  ).readAsStringSync();
  final client = File('lib/src/rust/api/client.dart').readAsStringSync();

  test('专用交互结果可构造且 Debug 不展开材料', () {
    final challenge = _Challenge();
    final answer = BridgeCaptchaAnswer(
      challenge: challenge,
      answer: 'synthetic-schema-answer',
    );
    final frame = BridgeCaptchaFrame(
      width: 1,
      height: 1,
      rgba: Uint8List.fromList(<int>[17, 83, 149, 255]),
    );
    final outcome = BridgeInteractiveLoginOutcome(
      login: _Login(),
      readiness: BridgeLoginReadiness.noneReady,
      routes: <BridgeInteractiveRouteResult>[
        BridgeInteractiveRouteResult(
          route: BridgeConnectionMode.direct,
          state: BridgeInteractiveRouteState.captchaRequired,
          challenge: challenge,
          revision: BigInt.one,
          validForMillis: 120000,
          frame: frame,
        ),
      ],
    );
    expect(
      '$answer $frame $outcome',
      isNot(contains('synthetic-schema-answer')),
    );
    expect('$answer $frame $outcome', isNot(contains('17, 83, 149')));
  });

  test('挑战保持 opaque，专用数据不生成 JSON 或服务器字段', () {
    expect(source, contains('abstract class BridgeCaptchaChallenge'));
    expect(source, contains('abstract class BridgeInteractiveLogin'));
    expect(source, isNot(contains('toJson')));
    expect(source, isNot(contains('fromJson')));
    expect(
      RegExp(
        r'final\s+String\??\s+(execution|captchaId|imageUrl|rawHtml|url)\s*;',
      ).hasMatch(source),
      isFalse,
    );
  });

  test('旧登录和普通结果不增加答案或像素', () {
    final login = RegExp(
      r'Future<BridgeLoginOutcome> login\(\{(.*?)\}\);',
      dotAll: true,
    ).firstMatch(client)!.group(1)!;
    expect(login, isNot(contains('captcha')));
    final outcome = RegExp(
      r'class BridgeLoginOutcome \{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(client)!.group(1)!;
    expect(outcome, isNot(contains('Captcha')));
    expect(outcome, isNot(contains('rgba')));
  });
}

class _Login implements BridgeInteractiveLogin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Challenge implements BridgeCaptchaChallenge {
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
