import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/materials.dart';
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

  for (final migrationFails in [false, true]) {
    testWidgets(migrationFails ? '迁移写失败后保存，重启仍合并旧地点' : '学号晚发布前保存地点，重启仍合并旧地点', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final values = _Preferences();
        final places = _openPlaces(values);
        const legacy = {
          UiPlaceKeys.libbookLibrary: '原图书馆',
          UiPlaceKeys.libbookArea: '原分区',
        };
        await places.write('fixture-student', legacy);
        final materials = syntheticMaterials(MemoryMaterials(), tester: tester);
        await materials.probe();
        final accounts = SecureLocalAccountStore(materials);
        await accounts.retain('fixture', retainSession: true);

        final profile = Completer<UserSummary?>();
        final backend = _Backend(profile: profile.future);
        Future<void> mount() => tester.pumpWidget(
          UbaaAppHost(
            backend: backend,
            preferenceValues: values,
            localAccountStore: accounts,
          ),
        );
        await mount();
        await pumpRecoveryUntil(tester, () => backend.profileReads > 0);
        expect(_shell(tester).user?.schoolId, isNull);
        Future<void> save() => _shell(tester).onSavePlacePreference!(
          UiPlaceKeys.libbookArea,
          '新分区',
        );
        if (migrationFails) {
          values.rejectPlaceWritesContaining = '原图书馆';
        } else {
          await save();
        }
        profile.complete(
          const UserSummary(username: 'fixture', schoolId: 'fixture-student'),
        );
        await pumpRecoveryUntil(
          tester,
          () => _shell(tester).user?.schoolId == 'fixture-student',
        );
        if (migrationFails) {
          await save();
          expect(values.rejectedPlaceWrites, greaterThan(0));
          expect(await places.read('fixture-student'), legacy);
          expect(await places.read('fixture'), {
            UiPlaceKeys.libbookArea: '新分区',
          });
        }
        await tester.pumpWidget(const SizedBox());

        values.rejectPlaceWritesContaining = null;
        await mount();
        const expected = {
          UiPlaceKeys.libbookLibrary: '原图书馆',
          UiPlaceKeys.libbookArea: '新分区',
        };
        await pumpRecoveryUntil(
          tester,
          () =>
              find.byType(UbaaMainShell).evaluate().isNotEmpty &&
              _shell(tester).user?.schoolId == 'fixture-student' &&
              _shell(tester).placePreferences[UiPlaceKeys.libbookArea] == '新分区',
        );
        expect(_shell(tester).placePreferences, expected);
        expect(await places.read('fixture'), expected);
        expect(await places.read('fixture-student'), isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  testWidgets('下次保存成功时也持久化前一次失败的地点改动', (tester) async {
    await tester.runAsync(() async {
      final values = _Preferences();
      Future<void> mount() async {
        await tester.pumpWidget(
          UbaaAppHost(backend: _Backend(), preferenceValues: values),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      final save = _shell(tester).onSavePlacePreference!;
      values.fail = true;
      await save(UiPlaceKeys.libbookLibrary, '新图书馆');
      values.fail = false;
      expect(await _openPlaces(values).read('fixture'), isEmpty);
      await save(UiPlaceKeys.libbookArea, '新分区');
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(_shell(tester).placePreferences, {
        UiPlaceKeys.libbookLibrary: '新图书馆',
        UiPlaceKeys.libbookArea: '新分区',
      });
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final username in ['fixture', 'other']) {
    testWidgets('退出后登录 $username 不接收上次未落盘的地点改动', (tester) async {
      await tester.runAsync(() async {
        final values = _Preferences();
        final places = _openPlaces(values);
        await tester.pumpWidget(
          UbaaAppHost(
            backend: _Backend(),
            preferenceValues: values,
            credentialVault: MemoryCredentialVault(),
          ),
        );
        await tester.pumpAndSettle();
        final oldShell = _shell(tester);
        values.fail = true;
        await oldShell.onSavePlacePreference!(
          UiPlaceKeys.libbookLibrary,
          '退出前选择',
        );
        values.fail = false;
        await oldShell.onLogout();
        await tester.pumpAndSettle();

        final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
        login.onUsernameChanged(username);
        login.onPasswordChanged('fixture-password');
        login.onSubmit();
        await tester.pumpAndSettle();
        await oldShell.onSavePlacePreference!(
          UiPlaceKeys.libbookLibrary,
          '旧账号回调',
        );
        await _shell(tester).onSavePlacePreference!(
          UiPlaceKeys.libbookArea,
          '登录后选择',
        );
        expect(await places.read(username), {UiPlaceKeys.libbookArea: '登录后选择'});
        if (username != 'fixture')
          expect(await places.read('fixture'), isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

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

UbaaMainShell _shell(WidgetTester tester) =>
    tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));

PlacePreferenceStore _openPlaces(_Preferences values) => PlacePreferenceStore(
  scope: 'synthetic',
  allowedKeys: UiPlaceKeys.all,
  values: values,
);

class _Backend extends DemoBackend {
  _Backend({this.profile}) : super(loginDelay: Duration.zero);

  final Future<UserSummary?>? profile;
  String? _username = 'fixture';
  int profileReads = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      _username == null ? AuthStatus.signedOut : AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async {
    profileReads++;
    if (profile case final pending?) return pending;
    return _username == null ? null : UserSummary(username: _username!);
  }

  @override
  Future<void> login(LoginInput input) async {
    _username = input.username;
  }

  @override
  Future<void> logout() async {
    _username = null;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}

class _Preferences implements PreferenceValues {
  final delegate = acceptedPrivacyPreferences();
  bool fail = false;
  String? rejectPlaceWritesContaining;
  int rejectedPlaceWrites = 0;
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
    if (rejectPlaceWritesContaining case final text?
        when key.startsWith('flutter.ubaa.preferences.v2.places.') &&
            value.contains(text)) {
      rejectedPlaceWrites++;
      throw StateError('合成迁移写入失败');
    }
    if (fail) throw StateError('合成存储失败');
    await delegate.write(key, value);
  }

  @override
  Future<void> remove(String key) => delegate.remove(key);
}
