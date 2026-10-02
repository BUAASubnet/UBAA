import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('组件从完整本地学期读取空周和原课程，不携带秘密或写资格', () async {
    final backend = _Cache();
    final value = await readScheduleWidgetSnapshot(
      backend: backend,
      owner: 'owner',
      policy: RoutePolicy.webvpn,
      isCurrent: () => true,
    );
    expect(value.semesters, hasLength(1));
    expect(value.semesters.single['name'], '合成学期');
    final weeks = value.semesters.single['weeks']! as List;
    expect(weeks, hasLength(2));
    expect((weeks.last as Map)['courses'], isEmpty);
    expect(value.toJson().toString(), contains('合成课程'));
    expect(
      ((weeks.first as Map)['courses'] as List).first['weeksAndTeachers'],
      '1–2周 合成教师',
    );
    expect(value.toJson().toString(), isNot(contains('不能导出')));
    expect(backend.queries.every((q) => q.$2 == RoutePolicy.webvpn), isTrue);
  });
  test('不完整周不能把部分学期发布为完整组件', () async {
    final value = await readScheduleWidgetSnapshot(
      backend: _Cache(incomplete: true),
      owner: 'owner',
      policy: RoutePolicy.webvpn,
      isCurrent: () => true,
    );
    expect(value.semesters, isEmpty);
  });
  test('错账号的缓存不能进入当前组件', () async {
    final value = await readScheduleWidgetSnapshot(
      backend: _Cache(account: 'other'),
      owner: 'owner',
      policy: RoutePolicy.webvpn,
      isCurrent: () => true,
    );
    expect(value.semesters, isEmpty);
  });
  test('退出后迟到的本地读取必须取消发布', () async {
    final backend = _Cache()..pending = Completer<void>();
    var current = true;
    final task = readScheduleWidgetSnapshot(
      backend: backend,
      owner: 'owner',
      policy: RoutePolicy.webvpn,
      isCurrent: () => current,
    );
    final result = expectLater(
      task,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          'code',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    current = false;
    backend.pending!.complete();
    await result;
  });
}

class _Cache implements OfflineQueryBackend {
  _Cache({this.incomplete = false, this.account = 'owner'});
  final bool incomplete;
  final String account;
  Completer<void>? pending;
  final queries = <(FeatureQuery, RoutePolicy)>[];
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    expect(feature, FeatureId.schedule);
    queries.add((query, policy));
    await pending?.future;
    final details = switch (query.view) {
      FeatureQueryView.scheduleTerms => [
        const FeatureDetail(
          title: '合成学期',
          presentation: TermPresentation(
            code: 'term',
            selected: true,
            index: 0,
          ),
        ),
      ],
      FeatureQueryView.scheduleWeeks => [
        for (var i = 1; i <= 2; i++)
          FeatureDetail(
            title: '第$i周',
            presentation: WeekPresentation(
              requestTerm: 'term',
              responseTerm: 'term',
              number: i,
              current: i == 1,
              startDate: i == 1 ? '2026-09-28' : '2026-10-05',
              endDate: i == 1 ? '2026-10-04' : '2026-10-11',
            ),
          ),
      ],
      FeatureQueryView.scheduleWeek =>
        query.week == 2
            ? <FeatureDetail>[]
            : [
                const FeatureDetail(
                  title: '合成课程',
                  fields: [FeatureField(label: '秘密', value: '不能导出')],
                  presentation: ScheduleCoursePresentation(
                    courseCode: 'code',
                    dayOfWeek: 1,
                    beginSection: 1,
                    endSection: 2,
                    beginTime: '08:00',
                    endTime: '09:35',
                    place: '合成教室',
                    weeksAndTeachers: '1–2周 合成教师',
                  ),
                ),
              ],
      _ => throw StateError('不得在线或读取其他领域'),
    };
    return OfflineQueryRead(
      CachedFeatureProjection(
        feature: feature,
        accountId: account,
        route: ConnectionMode.webvpn,
        fetchedAt: DateTime.utc(2026, 10, 1),
        complete:
            !(incomplete &&
                query.view == FeatureQueryView.scheduleWeek &&
                query.week == 2),
        query: query,
        details: details,
      ),
    );
  }
}
