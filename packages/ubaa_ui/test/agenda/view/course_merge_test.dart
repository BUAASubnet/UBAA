import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/calendar_values.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UbaaTheme;
import '../flow_test.dart' show app, opened;
import '../support.dart';
import 'view_modes_test.dart' show at;

AgendaEntry _school(
  AgendaFeature feature,
  String id,
  String title,
  AgendaTime start,
  AgendaTime end, {
  String? location,
}) {
  final timing = AgendaTiming(
    kind: AgendaTimingKind.period,
    start: start,
    end: end,
  );
  return AgendaEntry(
    school: SchoolAgendaItem(
      key: SchoolAgendaKey(source: feature.name, upstreamId: id),
      timing: timing,
      title: title,
      subtitle: '',
      location: location,
      statusLabel: '已缓存',
      upstreamStatus: AgendaUpstreamStatus(
        feature: feature,
        completed: false,
        signStatus: feature == AgendaFeature.signin ? 0 : null,
      ),
      navigation: AgendaNavigation(
        feature: feature,
        courseId: id,
        date: agendaDate(agendaValue(start)!),
      ),
      homeTodo: false,
    ),
    timing: timing,
    soon: false,
    completed: false,
    hidden: false,
  );
}

void main() {
  testWidgets('日程上课按钮随窗口启用并直接打开对应二维码', (tester) async {
    final backend = MemoryAgenda();
    backend.school.addAll([
      _school(
        AgendaFeature.schedule,
        'course',
        '合成课程',
        at(5, 9),
        at(5, 10),
      ).school!,
      _school(
        AgendaFeature.signin,
        'signin',
        '合成课程',
        at(5, 9),
        at(5, 10),
      ).school!,
    ]);
    final service = await opened(backend);
    final reads = <String>[];
    var instant = DateTime.utc(2026, 11, 5, 0, 49);
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        localizationsDelegates: UbaaTheme.localizationsDelegates,
        supportedLocales: UbaaTheme.supportedLocales,
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: 'synthetic',
            route: ConnectionMode.direct,
            term: 'synthetic',
            agendaClock: Clock(() => instant),
            onOpenSchool: (_) => fail('上课入口应直接打开二维码'),
            signinSnapshot: const FeatureSnapshot(
              feature: FeatureId.signin,
              status: FeatureLoadStatus.success,
              resolvedRoute: ConnectionMode.direct,
              details: [
                FeatureDetail(
                  title: '合成课程',
                  presentation: SigninPresentation(
                    courseId: 'signin',
                    actionTarget: 'qr-target',
                    signStatus: 0,
                    classBeginTime: '09:00',
                    classEndTime: '10:00',
                  ),
                ),
              ],
            ),
            onFetchSigninQr: (target, _) async {
              reads.add(target);
              return '合成二维码';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '上课');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text('上课前 10 分钟开放'), findsOneWidget);
    instant = DateTime.utc(2026, 11, 5, 0, 50);
    await tester.pump(const Duration(minutes: 1));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SigninQrSheet), findsOneWidget);
    expect(reads, ['qr-target']);
  });

  testWidgets('日程已签到课程在窗口内提供二维码，面板不轮询', (tester) async {
    final backend = MemoryAgenda();
    backend.school.add(
      _school(
        AgendaFeature.signin,
        'signin',
        '合成课程',
        at(5, 9),
        at(5, 10),
      ).school!,
    );
    final service = await opened(backend);
    var instant = DateTime.utc(2026, 11, 5, 0, 49);
    final reads = <String>[];
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        localizationsDelegates: UbaaTheme.localizationsDelegates,
        supportedLocales: UbaaTheme.supportedLocales,
        home: Scaffold(
          body: AgendaView(
            service: service,
            scopeKey: 'synthetic',
            route: ConnectionMode.direct,
            term: 'synthetic',
            agendaClock: Clock(() => instant),
            onOpenSchool: (_) => fail('二维码入口应直接打开面板'),
            signinSnapshot: const FeatureSnapshot(
              feature: FeatureId.signin,
              status: FeatureLoadStatus.success,
              resolvedRoute: ConnectionMode.direct,
              details: [
                FeatureDetail(
                  title: '合成课程',
                  presentation: SigninPresentation(
                    courseId: 'signin',
                    actionTarget: 'qr-target',
                    signStatus: 1,
                    classBeginTime: '09:00',
                    classEndTime: '10:00',
                  ),
                ),
              ],
            ),
            onFetchSigninQr: (target, _) async {
              reads.add(target);
              return '合成二维码';
            },
            onCheckSigninStatus: (_) async {
              checks++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '二维码');
    expect(find.text('已签到'), findsOneWidget);
    expect(button, findsNothing);
    instant = DateTime.utc(2026, 11, 5, 0, 50);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('已签到'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SigninQrSheet), findsOneWidget);
    expect(reads, ['qr-target', 'qr-target']);
    expect(checks, 0);
    await tester.binding.handlePopRoute();
    instant = DateTime.utc(2026, 11, 5, 2, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    expect(find.text('已签到'), findsOneWidget);
  });

  testWidgets('日程中的缓存签到条目没有在线目标时禁用上课按钮', (tester) async {
    final backend = MemoryAgenda();
    for (final feature in [AgendaFeature.schedule, AgendaFeature.signin]) {
      backend.school.add(
        _school(feature, feature.name, '合成课程', at(5, 9), at(5, 10)).school!,
      );
    }
    await tester.pumpWidget(app(await opened(backend)));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '上课'),
    );
    expect(button.onPressed, isNull);
  });

  test('同名同地点的连续小节合并为一段，跨过中间的上课条目', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 19),
      at(5, 19, 45),
      location: 'F1',
    );
    final signin = _school(
      AgendaFeature.signin,
      's',
      '合成课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final second = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 19, 50),
      at(5, 20, 35),
      location: 'F1',
    );
    final merged = agendaMergeCourses([signin, first, second]);
    expect(merged.map((e) => e.$1).toList(), [signin, first]);
    expect(merged.last.$2, agendaEnd(second));
  });

  test('间隔过长、地点不同或不同课程时保持分开', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 8),
      at(5, 8, 45),
      location: 'F1',
    );
    final late = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 10),
      at(5, 10, 45),
      location: 'F1',
    );
    final moved = _school(
      AgendaFeature.schedule,
      'c',
      '合成课程',
      at(5, 8, 50),
      at(5, 9, 35),
      location: 'F2',
    );
    final other = _school(
      AgendaFeature.schedule,
      'd',
      '另一课程',
      at(5, 8, 50),
      at(5, 9, 35),
      location: 'F1',
    );
    expect(agendaMergeCourses([first, moved, other, late]).length, 4);
  });

  test('同名且时段重叠的上课归入课程，其余上课保留', () {
    final first = _school(
      AgendaFeature.schedule,
      'a',
      '合成课程',
      at(5, 19),
      at(5, 19, 45),
      location: 'F1',
    );
    final second = _school(
      AgendaFeature.schedule,
      'b',
      '合成课程',
      at(5, 19, 50),
      at(5, 20, 35),
      location: 'F1',
    );
    final signin = _school(
      AgendaFeature.signin,
      's',
      '合成课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final stray = _school(
      AgendaFeature.signin,
      't',
      '其他课程',
      at(5, 19),
      at(5, 20, 35),
    );
    final result = agendaAttachSignins(
      agendaMergeCourses([signin, stray, first, second]),
    );
    expect(result.map((e) => e.$1).toList(), [stray, first]);
    expect(result.last.$3, signin);
    expect(result.last.$2, agendaEnd(second));
  });

  testWidgets('连续小节课程的详情显示与列表相同的起止时间', (tester) async {
    final backend = MemoryAgenda();
    for (final (id, start, end) in [
      ('p3', at(5, 9, 50), at(5, 10, 35)),
      ('p4', at(5, 10, 40), at(5, 11, 25)),
      ('p5', at(5, 11, 30), at(5, 12, 15)),
    ]) {
      backend.school.add(
        _school(
          AgendaFeature.schedule,
          id,
          '合成连堂课',
          start,
          end,
          location: 'F1',
        ).school!,
      );
    }
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('12:15'), findsOneWidget);
    await tester.tap(find.text('合成连堂课'));
    await tester.pumpAndSettle();
    expect(find.textContaining('09:50 — 12:15'), findsOneWidget);
    expect(find.text('09:50 — 10:35'), findsNothing);
  });
}
