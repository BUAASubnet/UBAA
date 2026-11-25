import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'widget_example.dart';

void main() {
  test('主考不重复作副行，下项无地点仍显示下一节，未来一周显示日期', () {
    final data = snapshot([
      event('考试', AgendaFeature.exam, start: wall(0, 8), end: wall(0, 10)),
      event('自建', null, start: wall(0, 11)),
      event('远期课程', AgendaFeature.schedule, start: wall(8, 8), end: wall(8, 9)),
    ]);
    final up = segment(data, 'upNext', wall(0, 9));
    expect(up['primary']['tag'], '考试');
    expect(up['secondary']['kind'], 'next');
    expect(up['secondary']['text'], '下一节 11:00');
    expect(up['secondary']['private'], true);
    final far = segment(data, 'upNext', wall(0, 12));
    expect(far['primary']['timeText'], '11-24 8:00');
    final only = snapshot([
      event('考试', AgendaFeature.exam, start: wall(0, 14), end: wall(0, 16)),
    ]);
    expect(segment(only, 'upNext', wall(0, 14, 30))['secondary'], isNull);
  });
  test('今天最多八行，截止计数只含本日尚未到期事项', () {
    final data = snapshot([
      for (var number = 0; number < 10; number++)
        event(
          '自建$number',
          null,
          start: wall(0, 12 + number),
          end: wall(0, 13 + number),
        ),
      event('待办甲', null, due: wall(0, 8)),
      event('待办乙', null, due: wall(0, 22)),
      event('明天的课', AgendaFeature.schedule, start: wall(1, 8), end: wall(1, 9)),
    ]);
    expect(segment(data, 'today', monday)['rows'], hasLength(8));
    expect(segment(data, 'today', monday)['dueLine'], '今天 2 项截止');
    expect(segment(data, 'today', wall(0, 8))['dueLine'], '今天 1 项截止');
    expect(segment(data, 'today', wall(0, 22))['dueLine'], isNull);
  });
  test('整日主副行、连堂和倒计时的闭开边界', () {
    final data = snapshot(example());
    for (final (hour, minute, title, text, tag, label, target, secondary) in [
      (6, 59, '高等数学', '8:00', null, null, null, null),
      (7, 0, '高等数学', '8:00', null, '还有', wall(0, 8), null),
      (7, 30, '高等数学', '8:00', null, '还有', wall(0, 8), null),
      (
        8,
        20,
        '高等数学',
        '8:00–9:35',
        null,
        '还剩',
        wall(0, 9, 35),
        '下一节 10:10 教一 B305',
      ),
      (9, 40, '大学英语', '10:10', null, '还有', wall(0, 10, 10), null),
      (12, 30, '研讨室预约', '14:00', '预约', null, null, null),
      (17, 30, '博雅讲座', '19:00', '博雅', null, null, null),
      (21, 0, '线性代数', '明天 8:00', null, null, null, null),
    ]) {
      final row = segment(data, 'upNext', wall(0, hour, minute));
      expect(row['state'], 'item');
      final primary = row['primary'];
      expect(
        [
          primary['title'],
          primary['timeText'],
          primary['tag'],
          primary['ongoing'],
          row['secondary']?['text'],
        ],
        [title, text, tag, label == '还剩', secondary],
      );
      expect(
        primary['countdown'],
        target == null ? null : {'label': label, 'target': seconds(target)},
      );
    }
    expect(segment(data, 'today', monday)['rows'], hasLength(4));
    expect(segment(data, 'today', wall(0, 21))['dayLabel'], '明天');
    expect(
      jsonEncode(data),
      jsonEncode(snapshot(example(), build: wall(0, 23, 59))),
    );
    expect(data['dayStart'], seconds(monday));
  });
  test('考试优先级、未知开考时间和跨午夜项', () {
    final data = snapshot([
      ...example(),
      event(
        '考试甲',
        AgendaFeature.exam,
        start: wall(0, 14),
        end: wall(0, 16),
        place: '主 M101 · 座位 23',
      ),
      event('考试乙', AgendaFeature.exam, start: wall(0, 18), end: wall(0, 19)),
      event('本机跨日', null, start: wall(0, 23), end: wall(1, 1)),
    ]);
    expect(
      segment(data, 'upNext', wall(0, 9))['secondary']['text'],
      '14:00 考试 · 主 M101 · 座位 23',
    );
    final testTime = segment(data, 'upNext', wall(0, 14, 30));
    expect(testTime['primary']['place'], '主 M101 · 座位 23');
    expect(testTime['secondary']['text'], '18:00 考试 · 考场待定');
    final cross = segment(data, 'upNext', wall(1, 0, 30))['primary'];
    expect(
      [
        cross['private'],
        cross['dayText'],
        cross['timeText'],
        cross['countdown'],
      ],
      [
        true,
        '',
        '23:00–1:00',
        {'label': '还剩', 'target': seconds(wall(1, 1))},
      ],
    );
    for (final end in [null, wall(0, 12)]) {
      final unknown = snapshot([
        ...example(),
        event(
          '考试',
          AgendaFeature.exam,
          allDay: end == null ? monday : null,
          end: end,
          place: '合成考场',
        ),
      ]);
      expect(
        segment(unknown, 'upNext', wall(0, 9))['secondary']['text'],
        '今天有考试 · 时间待定 · 合成考场',
      );
      final row = segment(unknown, 'today', monday)['rows'][0];
      expect(
        [row['timeText'], row['endText'], row['rangeText']],
        ['待定', end == null ? null : '12:00', null],
      );
      expect(
        segment(unknown, 'todo', monday)['smallRow']['sub'],
        '11-16 时间待定 · 合成考场',
      );
      if (end != null)
        expect(segment(unknown, 'todo', end)['smallRow'], isNull);
    }
  });
  test('覆盖、学期前后、降级和非候选', () {
    final course = event(
      '周一课',
      AgendaFeature.schedule,
      start: wall(7, 8),
      end: wall(7, 9),
    );
    expect(
      segment(snapshot([course]), 'upNext', wall(4, 21))['primary']['timeText'],
      '周一 8:00',
    );
    for (final data in [
      snapshot([course], sources: [coverage(1)]),
      snapshot([course], failure: CacheMaintenanceFailure.unavailable),
    ]) {
      for (final key in ['upNext', 'today'])
        expect(segment(data, key, wall(4, 21))['message'], '部分课表未载入');
    }
    for (final key in ['today', 'upNext']) {
      expect(
        segment(snapshot([], index: weeks(0, 1)), key, wall(6, 23))['state'],
        'termEnd',
      );
      expect(
        segment(snapshot([], index: weeks(28, 1)), key, monday)['state'],
        'none',
      );
    }
    final invisible = snapshot([
      for (final (feature, hidden, completed, homeTodo) in [
        (AgendaFeature.schedule, true, false, true),
        (AgendaFeature.bykc, false, true, true),
        (AgendaFeature.cgyy, false, false, false),
        (AgendaFeature.signin, false, false, true),
      ])
        event(
          '不可见',
          feature,
          start: wall(0, 12),
          end: wall(0, 13),
          hidden: hidden,
          completed: completed,
          homeTodo: homeTodo,
        ),
    ]);
    expect(jsonEncode(invisible), isNot(contains('不可见')));
  });
  test('无结束时间、同刻优先和不连续课程', () {
    final data = snapshot([
      event('本机', null, start: wall(0, 7)),
      ...example(),
      event(
        '同刻另一课',
        AgendaFeature.schedule,
        start: wall(0, 8),
        end: wall(0, 10),
      ),
      event('同刻预约', AgendaFeature.cgyy, start: wall(0, 8), end: wall(0, 10)),
      event(
        '高等数学',
        AgendaFeature.schedule,
        start: wall(0, 10, 5),
        end: wall(0, 11),
        place: '主楼 A201',
      ),
      event(
        '高等数学',
        AgendaFeature.schedule,
        start: wall(0, 11, 10),
        end: wall(0, 12),
        place: '主楼 B201',
      ),
    ]);
    expect(segment(data, 'upNext', monday)['primary']['private'], true);
    final primary = segment(data, 'upNext', wall(0, 7))['primary'];
    expect([primary['kind'], primary['extraCount']], ['course', 2]);
    expect(
      segment(data, 'today', monday)['rows'].where((r) => r['title'] == '高等数学'),
      hasLength(3),
    );
  });
  test('待办两个尺寸、跨日紧迫标记、数据时刻和过期文字', () {
    final rows = [
      event(
        '作业甲',
        AgendaFeature.judge,
        due: wall(0, 23, 59),
        submission: AgendaSubmission.partial,
      ),
      event('作业乙', AgendaFeature.spoc, due: wall(1, 18)),
      event('作业丙', null, due: wall(4, 20)),
      event('考试', AgendaFeature.exam, start: wall(3, 14), end: wall(3, 16)),
    ];
    final data = snapshot(
      rows,
      sources: [coverage(4), freshness(wall(-1, 20, 30))],
    );
    final todo = segment(data, 'todo', monday);
    expect(
      [
        todo['smallRow']['title'],
        todo['smallRow']['leftText'],
        todo['smallRow']['sub'],
        todo['smallFooter'],
        todo['mediumFooter'],
      ],
      ['作业甲', '今天 23:59', '希冀作业 · 部分完成', '还有 2 项', '还有 1 项'],
    );
    expect(todo['mediumRows'].map((row) => row['leftText']), [
      '还有 3 天',
      '今天 23:59',
      '明天 18:00',
    ]);
    expect(segment(data, 'todo', wall(1))['smallRow']['urgent'], true);
    expect(segment(data, 'todo', wall(2))['smallRow']['leftText'], '明天');
    expect(todo['staleText'], isNull);
    expect(segment(data, 'todo', wall(0, 20, 30))['staleText'], '截至 昨天 20:30');
    expect(segment(data, 'todo', wall(1))['staleText'], '截至 11-15 20:30');
    expect(segment(snapshot([]), 'todo', monday)['state'], 'noData');
  });
  test('共用合同样例与 Dart 输出一致', () {
    final file = File('../../fixtures/schedule_widget/snapshot_v2.json');
    expect(
      jsonEncode(jsonDecode(file.readAsStringSync())),
      jsonEncode(widgetFixture()),
    );
  });
  test('组件链接只接受当前账号的已知目标和精确参数', () {
    final prefix =
        'ubaa://widget/open?owner=${Uri.encodeQueryComponent(owner)}&target=';
    for (final target in [
      'home',
      'agendaTodo',
      'schedule&date=2026-11-16',
      'agenda&date=2026-11-16',
      'feature&feature=bykc&view=bykcChosenCourses',
    ]) {
      expect(parseWidgetLaunch('$prefix$target', owner: owner), isNotNull);
      expect(parseWidgetLaunch('$prefix$target', owner: '其他账号'), isNull);
    }
    for (final bad in [
      'schedule',
      'agenda&date=2026-02-30',
      'agenda&date=12026-11-16',
      'home&extra=1',
      'other',
      'feature&feature=signin',
      'feature&feature=judge&view=judgeDetail',
      'feature&feature=bykc&view=bykcDetail&courseId=${'甲' * 129}',
    ])
      expect(parseWidgetLaunch('$prefix$bad', owner: owner), isNull);
    final nav = agendaNavigation(AgendaNavigation(feature: AgendaFeature.bykc));
    expect(nav.query.view, FeatureQueryView.bykcChosenCourses);
  });
  test('所有来源的卡片与行链接保留完整账号、日期和公开参数', () {
    final prefix =
        'ubaa://widget/open?owner=%E8%99%9A%E6%9E%84+%E8%B4%A6%E5%8F%B7&target=';
    final course = Uri.encodeQueryComponent('课程甲'),
        assignment = Uri.encodeQueryComponent('作业甲');
    for (final (feature, suffix) in [
      (AgendaFeature.schedule, 'schedule&date=2026-11-16'),
      (null, 'agenda&date=2026-11-16'),
      (AgendaFeature.bykc, 'feature&feature=bykc&view=bykcDetail&courseId=7'),
      (AgendaFeature.cgyy, 'feature&feature=cgyy&view=cgyyOrders'),
      (
        AgendaFeature.exam,
        'feature&feature=exam&view=examArranged&term=${Uri.encodeQueryComponent(term)}',
      ),
      (
        AgendaFeature.spoc,
        'feature&feature=spoc&view=spocDetail&assignmentId=$assignment',
      ),
      (
        AgendaFeature.judge,
        'feature&feature=judge&view=judgeDetail&courseId=$course&assignmentId=$assignment',
      ),
      (AgendaFeature.ygdk, 'feature&feature=ygdk&view=summary'),
    ]) {
      final due = [
        AgendaFeature.spoc,
        AgendaFeature.judge,
        AgendaFeature.ygdk,
      ].contains(feature);
      final data = snapshot([
        event(
          '合成项',
          feature,
          start: due ? null : wall(0, 8),
          end: due ? null : wall(0, 9),
          due: due ? wall(0, 17) : null,
        ),
      ]);
      final up = segment(data, 'upNext', monday),
          today = segment(data, 'today', monday),
          todo = segment(data, 'todo', monday);
      expect(todo['cardLink'], '${prefix}agendaTodo');
      if (due) {
        expect(todo['smallRow']['link'], '$prefix$suffix');
        expect(up['cardLink'], '${prefix}home');
      } else {
        expect(up['cardLink'], '$prefix$suffix');
        expect(up['primary']['link'], '$prefix$suffix');
        expect(today['rows'][0]['link'], '$prefix$suffix');
        expect(today['cardLink'], '${prefix}schedule&date=2026-11-16');
      }
      expect(parseWidgetLaunch('$prefix$suffix', owner: owner), isNotNull);
    }
  });
  test('Unicode 显示上限、表段上限和 UTF-8 整体上限互相独立', () {
    final long = '😀' * 70;
    final simple = snapshot([
      event(long, null, start: wall(0, 8), end: wall(0, 9), place: long),
    ]);
    final row = segment(simple, 'upNext', monday)['primary'];
    expect(row['title'], '😀' * 64);
    expect(row['place'], '😀' * 64);
    final big = snapshot(
      [],
      semesters: [
        {'name': '界' * 350000},
      ],
    );
    for (final key in ['today', 'upNext', 'todo']) expect(big[key], isNull);
    expect(big['semesters'][0]['name'], '界' * 350000);
    final dense = snapshot([
      for (var number = 1; number <= 2001; number++)
        event('合成待办$number', null, due: monday.add(Duration(seconds: number))),
    ]);
    expect(dense['todo'], isNull);
    expect(dense['today'], isNotNull);
    expect(dense['upNext'], isNotNull);
  });
  test('查询降级或缺少周索引时，学期末以后仍为部分覆盖', () {
    for (final data in [
      snapshot(
        [],
        build: wall(7),
        index: weeks().take(1).toList(),
        failure: CacheMaintenanceFailure.unavailable,
      ),
      snapshot(
        [],
        build: wall(7),
        index: weeks().take(1).toList(),
        sources: [
          AgendaSource(
            feature: AgendaFeature.schedule,
            observations: [],
            missingScopes: [
              AgendaCacheScope(
                route: route,
                kind: AgendaCacheKind.scheduleWeeks,
                term: term,
              ),
            ],
            unprojectableCount: 0,
          ),
        ],
      ),
    ]) {
      expect(segment(data, 'upNext', wall(7))['state'], 'partial');
      expect(segment(data, 'today', wall(7))['state'], 'partial');
    }
  });
  test('组件链接拒绝非正博雅课程 ID 和纯空白参数', () {
    final prefix = Uri(
      scheme: 'ubaa',
      host: 'widget',
      path: '/open',
      queryParameters: {'owner': owner, 'target': 'feature'},
    );
    for (final suffix in [
      '&feature=bykc&courseId=0',
      '&feature=bykc&courseId=-1',
      '&feature=spoc&assignmentId=%20%09',
    ]) {
      expect(
        parseWidgetLaunch('$prefix$suffix', owner: owner),
        isNull,
        reason: suffix,
      );
    }
  });
  test('覆盖要求索引、唯一周、成功完整观察，明确缺失优先', () {
    final scope = AgendaCacheScope(
      route: route,
      kind: AgendaCacheKind.scheduleWeek,
      term: term,
      week: 1,
    );
    for (final (index, observations, missing) in [
      (<WeekPresentation>[], [observed(scope)], <AgendaCacheScope>[]),
      ([...weeks(), ...weeks()], [observed(scope)], <AgendaCacheScope>[]),
      (weeks(), [observed(scope, success: false)], <AgendaCacheScope>[]),
      (weeks(), [observed(scope)], [scope]),
      (
        weeks(),
        [observed(scope)],
        [
          AgendaCacheScope(
            route: route,
            kind: AgendaCacheKind.scheduleWeeks,
            term: term,
          ),
        ],
      ),
    ]) {
      final data = snapshot(
        example(),
        index: index,
        sources: [
          AgendaSource(
            feature: AgendaFeature.schedule,
            observations: observations,
            missingScopes: missing,
            unprojectableCount: 0,
          ),
        ],
      );
      expect(segment(data, 'upNext', monday)['state'], 'partial');
      expect(segment(data, 'today', monday)['state'], 'partial');
      expect(segment(data, 'upNext', wall(0, 8))['state'], 'item');
    }
  });
}
