import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';

void main() {
  test('DemoBackend 提供确定性的登录与只读功能夹具', () async {
    final backend = DemoBackend(loginDelay: Duration.zero);

    expect(await backend.authStatus(), AuthStatus.signedOut);
    expect(await backend.userInfo(), isNull);

    await backend.login(
      const LoginInput(username: '2020000000', password: 'demo-password'),
    );

    expect(await backend.authStatus(), AuthStatus.signedIn);
    expect((await backend.userInfo())?.username, '2020000000');

    final result = await backend.loadFeature(FeatureId.schedule);
    expect(result.summary, '今天有 3 节课程');
    expect(result.details.single.title, FeatureId.schedule.title);

    await backend.logout();
    expect(await backend.authStatus(), AuthStatus.signedOut);
    expect(await backend.userInfo(), isNull);
  });

  test('DemoBackend 拒绝空凭据并阻止未登录读取', () async {
    final backend = DemoBackend(loginDelay: Duration.zero);

    await expectLater(
      backend.login(const LoginInput(username: '', password: 'password')),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      backend.loadFeature(FeatureId.schedule),
      throwsA(isA<BackendException>()),
    );
  });

  test('演示课程包含四种节次状态及回放资料', () async {
    final backend = DemoBackend(loginDelay: Duration.zero);
    final courses = (await backend.spocFiles.courses()).data;
    final service = backend.classroom;
    final catalog = (await service.catalog(courses.single.courseId)).data;
    expect(catalog.sessions.map((period) => period.status), [
      ClassroomStatus.replay,
      ClassroomStatus.live,
      ClassroomStatus.noReplay,
      ClassroomStatus.upcoming,
    ]);
    for (final period in catalog.sessions) {
      final session = (await service.session(
        catalog.courseId,
        period.subId,
      )).data;
      expect(session.status, period.status);
      expect(
        session.sources.map((source) => source.kind),
        switch (period.status) {
          ClassroomStatus.replay => [
            ClassroomPlaybackKind.teacher,
            ClassroomPlaybackKind.slides,
          ],
          ClassroomStatus.live => [
            ClassroomPlaybackKind.teacher,
            ClassroomPlaybackKind.student,
          ],
          _ => <ClassroomPlaybackKind>[],
        },
      );
      if (period.status != ClassroomStatus.replay) continue;
      final guid = session.sources.first.resourceGuid!;
      expect(
        (await service.transcript(period.subId, guid)).data.segments,
        isNotEmpty,
      );
      expect(
        (await service.summary(period.subId, guid)).data.summary,
        isNotEmpty,
      );
      expect(
        (await service.slides(
          catalog.courseId,
          period.subId,
          guid,
        )).data.slides,
        isNotEmpty,
      );
    }
  });
}
