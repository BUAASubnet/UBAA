import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../support/bridge/classroom_client.dart';
import '../../support/bridge/recording_client.dart'
    show FixtureCharacterizationBridgeClient;

void main() {
  test('课堂读取保留五次实际路线和精确标识', () async {
    final client = ClassroomRecordingClient();
    final service = BridgeBackend(client).classroom!;
    final catalog = await service.catalog('SPOC-002');
    expect(catalog.route, ConnectionMode.webvpn);
    expect(catalog.data.courseId, '101');
    expect(catalog.data.title, '合成课堂');
    expect(catalog.data.teachers, ['合成教师']);
    expect(catalog.data.termName, '合成学期');
    expect(catalog.data.sessions.map((period) => period.status), [
      ClassroomStatus.live,
      ClassroomStatus.replay,
      ClassroomStatus.noReplay,
      ClassroomStatus.upcoming,
      ClassroomStatus.tencentMeeting,
      ClassroomStatus.other,
    ]);
    final period = catalog.data.sessions[1];
    expect(period.title, '合成节次');
    expect(period.week, 3);
    expect(period.room, '合成教室');
    expect(period.lecturer, '合成讲师');
    expect((period.startSecs, period.endSecs), (10, 20));

    final session = await service.session(catalog.data.courseId, period.subId);
    expect(session.route, ConnectionMode.webvpn);
    expect(session.data.title, '合成回放');
    expect(session.data.status, ClassroomStatus.replay);
    expect((session.data.startSecs, session.data.endSecs), (10, 20));
    expect(session.data.sources.map((source) => source.kind), [
      ClassroomPlaybackKind.teacher,
      ClassroomPlaybackKind.slides,
      ClassroomPlaybackKind.student,
    ]);
    final source = session.data.sources.first;
    expect(source.url, 'https://example.invalid/fixture.mp4');
    expect(source.durationSecs, 120);
    expect(source.timeOffsetSecs, -12);
    expect(source.resourceGuid, 'fixture123');
    final student = session.data.sources.last;
    expect(
      (student.durationSecs, student.timeOffsetSecs, student.resourceGuid),
      (null, null, null),
    );

    final transcript = await service.transcript(
      period.subId,
      source.resourceGuid!,
    );
    final segment = transcript.data.segments.single;
    expect(transcript.route, ConnectionMode.webvpn);
    expect((segment.beginMs, segment.endMs, segment.text), (125, 500, '合成转写'));

    final summary = await service.summary(period.subId, source.resourceGuid!);
    expect(summary.route, ConnectionMode.webvpn);
    expect(summary.data.summary, '合成摘要');
    expect(summary.data.keywords, ['关键词']);
    final question = summary.data.qa.single;
    expect(
      (question.question, question.answer, question.startMs),
      ('提问', '回答', 125),
    );
    final chapter = summary.data.chapters.single;
    expect(
      (chapter.startMs, chapter.endMs, chapter.headline, chapter.summary),
      (125, 500, '章节', '简介'),
    );

    final slides = await service.slides(
      catalog.data.courseId,
      period.subId,
      source.resourceGuid!,
    );
    expect(slides.route, ConnectionMode.webvpn);
    final slide = slides.data.slides.single;
    expect(slide.offsetMs, 500);
    expect(slide.imageUrl, 'https://example.invalid/slide.png');
    expect(slide.thumbUrl, 'https://example.invalid/thumb.png');
    expect(client.calls, [
      'catalog:SPOC-002',
      'session:101:102',
      'transcript:102:fixture123',
      'summary:102:fixture123',
      'slides:101:102:fixture123',
    ]);
    expect(
      BridgeBackend(FixtureCharacterizationBridgeClient()).classroom,
      isNull,
    );
  });

  test('课堂错误按稳定诊断原因显示中文并保留路线', () async {
    final client = ClassroomRecordingClient();
    final service = BridgeBackend(client).classroom!;
    for (final (code, reason, expected) in [
      (BridgeErrorCode.unsupported, 'role_teacher_unsupported', '暂不支持教师身份'),
      (BridgeErrorCode.unsupported, 'role_unsupported', '暂不支持当前身份'),
      (BridgeErrorCode.unsupported, 'role_shape', '暂不支持当前身份'),
      (BridgeErrorCode.businessUnavailable, 'bind_id_missing', '该课程未开通课堂直录播'),
      (
        BridgeErrorCode.businessUnavailable,
        'mapping_unbound_page',
        '该课程暂未在智学北航开通课堂',
      ),
    ]) {
      final retryable = code == BridgeErrorCode.businessUnavailable;
      client.classroomError = BridgeError(
        code: code,
        kind: BridgeErrorKind.upstream,
        retryable: retryable,
        resolvedRoute: BridgeConnectionMode.webVpn,
        message: '不会传给界面的原文',
        diagnosticJson:
            '{"source":"crates/ubaa_core/src/features/spoc/classroom.rs:72",'
            '"stage":"spoc_mapping","reason":"$reason"}',
      );
      await expectLater(
        service.catalog('SPOC-002'),
        throwsA(
          isA<BackendException>()
              .having(
                (error) => error.resolvedRoute,
                '实际路线',
                ConnectionMode.webvpn,
              )
              .having((error) => error.retryable, '可重试', retryable)
              .having(
                (error) => UbaaErrorMapper.fromException(error).message,
                '提示',
                expected,
              ),
        ),
      );
    }
  });
}
