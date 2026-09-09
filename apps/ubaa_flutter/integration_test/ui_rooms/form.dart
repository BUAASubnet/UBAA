part of '../ui_rooms_test.dart';

void _registerRoomFormTests(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final scenario in ['selection', 'retry', 'route-invalidation']) {
      testWidgets('研讨室独立表单 $scenario ${brightness.name}', (tester) async {
        final backend = _PurposeRoomBackend(scenario);
        await _mount(tester, backend, brightness);
        await _tap(tester, find.byTooltip('合成研讨室 1 08:00–09:00'));
        await _tap(tester, find.text('下一步'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        Future<void> shot(String state, String steps) => _shot(
          binding,
          tester,
          '${brightness.name}-form-$scenario-$state',
          steps,
        );
        await shot('ready', '独立表单的已选时段、预约信息、附加选项；无常驻编号/刷新行');
        if (scenario == 'route-invalidation') {
          await _edit(tester, '联系电话', 'synthetic-private-draft');
          await _tap(tester, find.byTooltip('实际路线：直连'));
          await _tap(tester, find.byType(DropdownButton<RoutePolicy>));
          await _tap(tester, find.text(RoutePolicy.webvpn.label).last);
          expect(find.byType(UbaaLoginView), findsOneWidget);
          expect(find.text('填写研讨室预约信息'), findsNothing);
          expect(find.text('synthetic-private-draft'), findsNothing);
          await shot('cleared', '切未认证路线后回到登录，旧表单与内存草稿关闭');
          expect(backend.preparedRooms, isEmpty);
          expect(backend.commitCalls, 0);
          return;
        }
        if (scenario == 'retry') {
          expect(find.text('网络不可用'), findsOneWidget);
          await _tap(tester, find.widgetWithText(TextButton, '重试'));
          expect(backend.purposeCalls, 2);
        }
        await _tap(tester, find.widgetWithText(OutlinedButton, '合成研讨甲'));
        await shot('choices', '按需类型列表使用原key，可刷新及兼容手填；正文不堆工具栏');
        await _tap(tester, find.text('合成研讨乙'));
        for (final entry in {
          '联系电话': 'synthetic-phone',
          '预约主题': 'synthetic theme',
          '参与人数': '2',
          '活动内容': 'synthetic content',
          '参与人说明': 'synthetic participants',
        }.entries) {
          await _edit(tester, entry.key, entry.value);
        }
        await _tap(tester, find.text('哲学社会科学类活动'));
        await _tap(tester, find.text('含校外参与人'));
        await shot('filled', '多行内容/参与人及两个附加选项，原字段未删减');
        await _tap(tester, find.text('返回修改时段'));
        await _tap(tester, find.text('下一步'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '联系电话'))
              .controller!
              .text,
          'synthetic-phone',
        );
        await _tap(tester, find.text('继续确认'));
        final input = backend.preparedRooms.single;
        expect(input.purposeType, 37);
        expect(input.isPhilosophySocialSciences, isTrue);
        expect(input.isOffSchoolJoiner, isTrue);
        expect(input.joinerNum, 2);
        await shot('confirm', '返回后草稿仍在，继续只准备原typed输入，不执行真实或合成commit');
        await _tap(tester, find.byTooltip('取消并返回'));
        expect(backend.commitCalls, 0);
      });
    }
  }
}

class _PurposeRoomBackend extends RoomBackend {
  _PurposeRoomBackend(this.scenario);
  final String scenario;
  int purposeCalls = 0;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.cgyy ||
        query.view != FeatureQueryView.cgyyPurposeTypes) {
      return super.loadFeatureQuery(feature, query);
    }
    purposeCalls++;
    if (scenario == 'retry' && purposeCalls == 1) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return const FeatureResult.success(
      resolvedRoute: ConnectionMode.direct,
      details: [
        FeatureDetail(
          title: '错误展示999',
          presentation: CgyyPurposePresentation(
            key: 9,
            name: '合成研讨甲',
            isStaticFallback: true,
          ),
        ),
        FeatureDetail(
          title: '错误展示888',
          presentation: CgyyPurposePresentation(
            key: 37,
            name: '合成研讨乙',
            isStaticFallback: true,
          ),
        ),
      ],
    );
  }
}
