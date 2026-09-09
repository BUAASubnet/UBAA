part of '../ui_library_test.dart';

void registerLibraryParentTests(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final state in ['normal', 'missing-parents', 'conflicting-parents']) {
      testWidgets('原生图书馆父标识 $state ${brightness.name}', (tester) async {
        final backend = LibraryBackend(state: state);
        await _mount(tester, backend, brightness);
        final conflicting = state == 'conflicting-parents';
        expect(
          backend.libraryReads.last.view,
          conflicting
              ? FeatureQueryView.libbookAreas
              : FeatureQueryView.libbookAreaDetail,
        );
        await _shot(
          binding,
          tester,
          '${brightness.name}-$state-flow',
          conflicting ? '明确冲突的父标识不自动进入详情' : '原父字段完整或缺省均沿实际查询进入原分区详情',
        );
        if (conflicting) return;
        await _seatQuery(tester, backend);
        expect(backend.libraryReads.last.view, FeatureQueryView.libbookSeats);
        expect(backend.preparedSeats, isEmpty);
        await _shot(
          binding,
          tester,
          '${brightness.name}-$state-seats',
          '明确日期与原时段后只查询座位，不准备或提交',
        );
        await _tap(tester, find.widgetWithText(FilterChip, '合成乙馆 3/40'));
        expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
        expect(find.text('已选座位：A1'), findsNothing);
        await _shot(
          binding,
          tester,
          '${brightness.name}-$state-other-library',
          '切换楼馆按新请求继续缺省父字段分区，旧选择失效',
        );
        expect(backend.commitCalls, 0);
      });
    }
  }
}
