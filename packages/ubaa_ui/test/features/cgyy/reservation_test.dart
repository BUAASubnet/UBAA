import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/write_harness.dart';
import '../../support/navigation.dart';
import '../../support/ui/cgyy_writes.dart' show fixtureFillCgyyForm;

const _cgyyUiFirstAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 900,
  venueSpaceGroupId: 9,
  timeOrdinal: 0,
  eligibility: ActionEligibility.allowed,
);

const _cgyyUiSecondAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 100,
  venueSpaceGroupId: 9,
  timeOrdinal: 1,
  eligibility: ActionEligibility.allowed,
);

const _cgyyUiThirdAction = CgyyReserveAction(
  venueSiteId: 3,
  reservationDate: '2026-09-03',
  spaceId: 4,
  timeId: 700,
  venueSpaceGroupId: 9,
  timeOrdinal: 2,
  eligibility: ActionEligibility.allowed,
);

void _registerCgyyReservationWriteTests() {
  testWidgets('研讨室表单底部按钮不被上一操作的SnackBar遮挡', (tester) async {
    await _pumpCgyyShell(
      tester,
      details: const [
        FeatureDetail(title: '合成时段', actions: [_cgyyUiFirstAction]),
      ],
      onPrepare: (_) async => _cgyyIntent(),
    );
    await tester.tap(_cgyyButtonFor('合成时段'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '继续确认');
    ScaffoldMessenger.of(tester.element(button)).showSnackBar(
      const SnackBar(content: Text('上一操作结果'), duration: Duration(minutes: 1)),
    );
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('研讨室预约在 action 缺失、denied 或 unknown 时默认拒绝', (tester) async {
    var prepareCalls = 0;
    await _pumpCgyyShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '缺失 action 的时段',
          fields: <FeatureField>[
            FeatureField(label: '站点 ID', value: '3'),
            FeatureField(label: '日期', value: '2026-09-03'),
            FeatureField(label: '空间 ID', value: '4'),
            FeatureField(label: '时段 ID', value: '900'),
            FeatureField(label: '可预约', value: '是'),
          ],
        ),
        FeatureDetail(
          title: 'denied 时段',
          fields: <FeatureField>[FeatureField(label: '可预约', value: '是')],
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-03',
              spaceId: 4,
              timeId: 901,
              venueSpaceGroupId: 9,
              timeOrdinal: 1,
              eligibility: ActionEligibility.denied,
            ),
          ],
        ),
        FeatureDetail(
          title: 'unknown 时段',
          fields: <FeatureField>[FeatureField(label: '可预约', value: '是')],
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-03',
              spaceId: 4,
              timeId: 902,
              venueSpaceGroupId: 9,
              timeOrdinal: 2,
              eligibility: ActionEligibility.unknown,
            ),
          ],
        ),
      ],
      onPrepare: (_) async {
        prepareCalls++;
        throw StateError('非 Allowed action 不应进入研讨室预约 prepare');
      },
    );

    expect(_cgyyButtonFor('缺失 action 的时段'), findsNothing);
    expect(_cgyyButtonFor('denied 时段'), findsNothing);
    expect(_cgyyButtonFor('unknown 时段'), findsNothing);
    expect(prepareCalls, 0);
  });

  testWidgets('场馆候选只保留同目标且按 ordinal 执行相邻、上限与重置规则', (tester) async {
    CgyySubmitInput? captured;
    await _pumpCgyyShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '时段一',
          fields: <FeatureField>[
            FeatureField(label: '任意展示标签', value: '与目标无关'),
            FeatureField(label: '可预约', value: '否'),
          ],
          actions: <FeatureAction>[_cgyyUiFirstAction],
        ),
        FeatureDetail(
          title: '时段二',
          actions: <FeatureAction>[_cgyyUiSecondAction],
        ),
        FeatureDetail(
          title: '时段三',
          actions: <FeatureAction>[_cgyyUiThirdAction],
        ),
        FeatureDetail(
          title: '跨站点时段',
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 8,
              reservationDate: '2026-09-03',
              spaceId: 4,
              timeId: 710,
              venueSpaceGroupId: 9,
              timeOrdinal: 3,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
        FeatureDetail(
          title: '跨日期时段',
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-04',
              spaceId: 4,
              timeId: 720,
              venueSpaceGroupId: 9,
              timeOrdinal: 3,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
        FeatureDetail(
          title: '跨空间时段',
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-03',
              spaceId: 5,
              timeId: 730,
              venueSpaceGroupId: 9,
              timeOrdinal: 3,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
        FeatureDetail(
          title: '跨空间组时段',
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-03',
              spaceId: 4,
              timeId: 740,
              venueSpaceGroupId: 10,
              timeOrdinal: 3,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
      ],
      onPrepare: (input) async {
        captured = input;
        return _cgyyIntent();
      },
    );

    await tester.tap(_cgyyButtonFor('时段一'));
    await tester.pumpAndSettle();
    expect(find.text('选择预约时段（已选 1 个）'), findsOneWidget);
    expect(_cgyyChip(900), findsOneWidget);
    expect(_cgyyChip(100), findsOneWidget);
    expect(_cgyyChip(700), findsOneWidget);
    expect(_cgyyChip(710), findsNothing);
    expect(_cgyyChip(720), findsNothing);
    expect(_cgyyChip(730), findsNothing);
    expect(_cgyyChip(740), findsNothing);

    await tester.tap(_cgyyChip(700));
    await tester.pumpAndSettle();
    expect(find.text('选择预约时段（已选 1 个）'), findsOneWidget);
    expect(tester.widget<FilterChip>(_cgyyChip(900)).selected, isFalse);
    expect(tester.widget<FilterChip>(_cgyyChip(700)).selected, isTrue);

    await tester.tap(_cgyyChip(100));
    await tester.pumpAndSettle();
    expect(find.text('选择预约时段（已选 2 个）'), findsOneWidget);
    expect(tester.widget<FilterChip>(_cgyyChip(100)).selected, isTrue);
    expect(tester.widget<FilterChip>(_cgyyChip(700)).selected, isTrue);

    await tester.tap(_cgyyChip(900));
    await tester.pumpAndSettle();
    expect(find.text('选择预约时段（已选 1 个）'), findsOneWidget);
    expect(tester.widget<FilterChip>(_cgyyChip(900)).selected, isTrue);
    expect(tester.widget<FilterChip>(_cgyyChip(100)).selected, isFalse);
    expect(tester.widget<FilterChip>(_cgyyChip(700)).selected, isFalse);

    await fixtureFillCgyyForm(tester, joiners: '  张三  ');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(captured?.actions, hasLength(1));
    expect(identical(captured?.actions.single, _cgyyUiFirstAction), isTrue);
    expect(captured?.joiners, '张三');
    expect(find.text('确认研讨室预约'), findsOneWidget);
  });

  testWidgets('场馆表单把 trim 后为空的参与人说明视为必填', (tester) async {
    var prepareCalls = 0;
    CgyySubmitInput? captured;
    await _pumpCgyyShell(
      tester,
      details: const <FeatureDetail>[
        FeatureDetail(
          title: '可预约时段',
          actions: <FeatureAction>[_cgyyUiFirstAction],
        ),
      ],
      onPrepare: (input) async {
        prepareCalls++;
        captured = input;
        return _cgyyIntent();
      },
    );

    await tester.tap(_cgyyButtonFor('可预约时段'));
    await tester.pumpAndSettle();
    await fixtureFillCgyyForm(tester, joiners: '   ');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 0);
    expect(find.widgetWithText(AppBar, '填写预约信息'), findsOneWidget);

    await tester.enterText(fixtureCgyyTextField('参与人说明'), '  张三  ');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(captured?.joiners, '张三');
  });
}

Future<void> _pumpCgyyShell(
  WidgetTester tester, {
  required List<FeatureDetail> details,
  required CgyyReservationPreparer onPrepare,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: coordinatedShell(
        user: const UserSummary(username: 'student'),
        snapshots: <FeatureId, FeatureSnapshot>{
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(
              feature: feature,
              status: FeatureLoadStatus.success,
              summary: '已加载',
              details: feature == FeatureId.cgyy
                  ? details
                  : const <FeatureDetail>[],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onPrepareCgyySubmitWrite: onPrepare,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.byIcon(UiDestination.campus.icon));
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.cgyy);
  await tester.pumpAndSettle();
}

Finder fixtureCgyyTextField(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText?.contains(label) == true,
  description: 'label 含“$label”的场馆表单输入框',
);

Finder _cgyyButtonFor(String title) {
  final card = find.ancestor(of: find.text(title), matching: find.byType(Card));
  return find.descendant(
    of: card,
    matching: find.widgetWithText(OutlinedButton, '准备研讨室预约'),
  );
}

Finder _cgyyChip(int timeId) =>
    find.widgetWithText(FilterChip, '空间 4 · 时段 $timeId');

WriteIntent _cgyyIntent() => WriteIntent(
  intentId: 'cgyy-reserve-red',
  operation: WriteOperation.cgyySubmitReservation,
  targetSummary: '研讨室预约',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'digest',
);

void main() {
  _registerCgyyReservationWriteTests();
}
