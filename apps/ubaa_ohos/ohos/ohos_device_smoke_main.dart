import 'package:flutter/material.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

Future<void> main() async {
  await RustLib.init();
  final result = bridgeHello();
  debugPrint(
    'FRB_OHOS_SMOKE_RESULT=${result == 'UBAA FRB 2.13.0 ready' ? 'PASS' : 'FAIL'}',
  );
  runApp(_SmokeApp(result: result));
}

class _SmokeApp extends StatelessWidget {
  const _SmokeApp({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text('FRB: $result'))),
  );
}
