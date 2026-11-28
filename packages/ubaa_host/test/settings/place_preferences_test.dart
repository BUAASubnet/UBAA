import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/privacy.dart';

void main() {
  testWidgets('地点恢复未完成时保存，重读仍保留其他地点', (tester) async {
    await tester.runAsync(() async {
      final values = _Preferences();
      PlacePreferenceStore openPlaces() => PlacePreferenceStore(
        scope: 'synthetic',
        allowedKeys: UiPlaceKeys.all,
        values: values,
      );
      await openPlaces().write('fixture', {
        UiPlaceKeys.libbookLibrary: '原图书馆',
        UiPlaceKeys.libbookArea: '原分区',
      });
      final restore = Completer<void>();
      values.nextPlaceRead = restore.future;
      await tester.pumpWidget(
        UbaaAppHost(backend: _Backend(), preferenceValues: values),
      );
      await tester.pumpAndSettle();
      expect(values.nextPlaceRead, isNull);
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.placePreferences, isEmpty);

      final saving = shell.onSavePlacePreference!(
        UiPlaceKeys.libbookArea,
        '新分区',
      );
      restore.complete();
      await saving;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());

      expect(await openPlaces().read('fixture'), {
        UiPlaceKeys.libbookLibrary: '原图书馆',
        UiPlaceKeys.libbookArea: '新分区',
      });
    });
  });

  testWidgets('宿主恢复地点、保存、清账号并保留设备主题和其他账号', (tester) async {
    await tester.runAsync(() async {
      final values = _Preferences();
      final places = PlacePreferenceStore(
        scope: 'synthetic',
        allowedKeys: UiPlaceKeys.all,
        values: values,
      );
      await places.write('fixture', {UiPlaceKeys.libbookLibrary: '合成馆'});
      await places.write('other', {UiPlaceKeys.libbookLibrary: '其他馆'});
      final theme = ThemePreferenceStore(values: values);
      await theme.write('dark');
      await tester.pumpWidget(
        UbaaAppHost(backend: _Backend(), preferenceValues: values),
      );
      await tester.pumpAndSettle();
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.placePreferences, {UiPlaceKeys.libbookLibrary: '合成馆'});
      expect(shell.appearance.themeMode, ThemeMode.dark);
      await shell.onSavePlacePreference!(UiPlaceKeys.libbookArea, '合成分区');
      expect((await places.read('fixture'))[UiPlaceKeys.libbookArea], '合成分区');
      await shell.onSavePlacePreference!('未知键', '拒绝值');
      expect((await places.read('fixture')).containsKey('未知键'), isFalse);
      values.fail = true;
      await shell.onSavePlacePreference!(UiPlaceKeys.libbookArea, '失败保存');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      values.fail = false;
      await shell.onLogoutAndClearAccount();
      expect(await places.read('fixture'), isEmpty);
      expect(await places.read('other'), {UiPlaceKeys.libbookLibrary: '其他馆'});
      expect(await theme.read(), 'dark');
      await shell.onSavePlacePreference!(UiPlaceKeys.libbookArea, '旧回调');
      expect(await places.read('fixture'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _Backend extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}

class _Preferences implements PreferenceValues {
  final delegate = acceptedPrivacyPreferences();
  bool fail = false;
  Future<void>? nextPlaceRead;
  @override
  Future<String?> read(String key) async {
    if (key.startsWith('flutter.ubaa.preferences.v2.places.')) {
      final delay = nextPlaceRead;
      nextPlaceRead = null;
      await delay;
    }
    return delegate.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('合成存储失败');
    await delegate.write(key, value);
  }

  @override
  Future<void> remove(String key) => delegate.remove(key);
}
