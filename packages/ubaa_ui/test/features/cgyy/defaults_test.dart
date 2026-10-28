import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write/cgyy/draft.dart';
import 'package:ubaa_ui/src/write/cgyy/form.dart';

const target = CgyyReserveAction(
  venueSiteId: 7,
  reservationDate: '2026-10-28',
  spaceId: 4,
  timeId: 9,
  timeOrdinal: 0,
  venueSpaceGroupId: null,
  eligibility: ActionEligibility.allowed,
);
const defaults = CgyyReservationDefaults(
  phone: 'synthetic-phone',
  theme: '合成主题',
  purposeType: 37,
  joinerNum: '3',
  activityContent: '讨论',
  joiners: '合成人员',
);
void main() {
  for (final edited in [false, true]) {
    testWidgets('空字段使用灰字，编辑后使用新值并在校验通过后保存：编辑=$edited', (tester) async {
      CgyySubmitInput? result;
      final saved = <CgyyReservationDefaults>[];
      await open(tester, defaults, saved, (v) => result = v);
      final phone = find.widgetWithText(TextField, '联系电话');
      expect(tester.widget<TextField>(phone).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(phone).decoration!.hintText,
        defaults.phone,
      );
      if (edited) await tester.enterText(phone, 'new-synthetic-phone');
      expect(saved, isEmpty);
      await tester.tap(find.text('继续确认'));
      await tester.pumpAndSettle();
      expect(result?.phone, edited ? 'new-synthetic-phone' : defaults.phone);
      expect(result?.purposeType, 37);
      expect(result?.joinerNum, 3);
      expect(result?.theme, defaults.theme);
      expect(result?.activityContent, defaults.activityContent);
      expect(result?.joiners, defaults.joiners);
      expect(saved.single.phone, result?.phone);
    });
  }
  testWidgets('用途不可用时标记活动类型且不保存或提交', (tester) async {
    final saved = <CgyyReservationDefaults>[];
    await open(
      tester,
      defaults,
      saved,
      (_) => fail('用途缺失不得提交'),
      purposesAvailable: false,
    );
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == '活动类型',
    );
    expect(
      tester.widget<InputDecorator>(field).decoration.errorText,
      '请选择活动类型',
    );
    expect(saved, isEmpty);
  });
  testWidgets('逐项标记缺失字段，填好一项后消除该项错误且不保存无效表单', (tester) async {
    final saved = <CgyyReservationDefaults>[];
    await open(tester, null, saved, (_) => fail('无效表单不得提交'));
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    for (final label in ['联系电话', '预约主题', '活动内容', '参与人说明']) {
      final field = find.widgetWithText(TextField, label);
      await tester.ensureVisible(field);
      expect(
        tester.widget<TextField>(field).decoration!.errorText,
        '请填写$label',
      );
      await tester.enterText(field, '合成内容');
      await tester.pump();
      expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
    }
    final people = find.widgetWithText(TextField, '参与人数');
    await tester.ensureVisible(people);
    await tester.enterText(people, '0');
    await tester.pump();
    expect(tester.widget<TextField>(people).decoration!.errorText, '请填写正整数');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });
}

Future<void> open(
  WidgetTester tester,
  CgyyReservationDefaults? value,
  List<CgyyReservationDefaults> saved,
  void Function(CgyySubmitInput?) done, {
  bool purposesAvailable = true,
}) async {
  final draft = CgyyFormDraft();
  addTearDown(draft.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => done(
              await uiCollectCgyyReservation(
                context,
                target,
                [target],
                formContext: CgyyFormContext(
                  draft: draft,
                  loadDefaults: () async => value,
                  saveDefaults: (v) async => saved.add(v),
                  loadPurposes: (_) async => !purposesAvailable
                      ? const FeatureResult.empty()
                      : const FeatureResult.success(
                          details: [
                            FeatureDetail(
                              title: '合成用途',
                              presentation: CgyyPurposePresentation(
                                key: 37,
                                name: '合成用途',
                                isStaticFallback: false,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
