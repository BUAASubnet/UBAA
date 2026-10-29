import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../support/assignments/backend.dart';
import '../support/navigation/native.dart';

class _Information implements PlatformAppInformation {
  @override
  Future<String?> version() async => '0.1.0+1';
  @override
  Future<bool> open(AppLink link) async => true;
}

void main() {
  for (final width in [390.0, 800.0, 1200.0]) {
    testWidgets('原生测试沿当前可见导航打开关于：宽度 $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        UbaaFlutterApp(
          backend: CourseworkBackend()..signedIn = true,
          credentialVault: MemoryCredentialVault(),
          appInformation: _Information(),
          initialDestination: UiDestination.academic,
        ),
      );
      await tester.pumpAndSettle();
      await uiOpenUtility(tester, '关于');
      expect(find.widgetWithText(AppBar, '关于'), findsOneWidget);
      expect(find.textContaining('0.1.0+1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
