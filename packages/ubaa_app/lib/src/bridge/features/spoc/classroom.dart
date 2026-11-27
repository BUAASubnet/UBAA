import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

final class BridgeClassroomService implements ClassroomService {
  const BridgeClassroomService(this.client);
  final BridgeClient client;

  Future<ClassroomRead<T>> _read<T>(
    Future<({T data, BridgeRouteDecision route})> Function() call,
  ) async {
    try {
      final result = await call();
      return (
        data: result.data,
        route: bridgeToConnectionMode(result.route.resolvedRoute),
      );
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) =>
      _read(() async {
        final result = await client.spocClassroomCatalog(kcid: kcid);
        final catalog = result.data;
        return (
          route: result.route,
          data: ClassroomCatalog(
            courseId: catalog.courseId,
            title: catalog.title,
            teachers: catalog.teachers,
            termName: catalog.termName,
            sessions: [
              for (final period in catalog.sessions)
                ClassroomSessionSummary(
                  subId: period.subId,
                  title: period.title,
                  week: period.week,
                  startSecs: period.startSecs.toInt(),
                  endSecs: period.endSecs.toInt(),
                  room: period.room,
                  lecturer: period.lecturer,
                  status: _status(period.status),
                ),
            ],
          ),
        );
      });

  @override
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  ) => _read(() async {
    final result = await client.spocClassroomSession(
      courseId: courseId,
      subId: subId,
    );
    final session = result.data;
    return (
      route: result.route,
      data: ClassroomSession(
        title: session.title,
        startSecs: session.startSecs.toInt(),
        endSecs: session.endSecs.toInt(),
        status: _status(session.status),
        sources: [
          for (final source in session.sources)
            ClassroomPlaybackSource(
              kind: switch (source.kind) {
                BridgeClassroomPlaybackKind.teacher =>
                  ClassroomPlaybackKind.teacher,
                BridgeClassroomPlaybackKind.slides =>
                  ClassroomPlaybackKind.slides,
                BridgeClassroomPlaybackKind.student =>
                  ClassroomPlaybackKind.student,
              },
              url: source.url,
              durationSecs: source.durationSecs?.toInt(),
              timeOffsetSecs: source.timeOffsetSecs?.toInt(),
              resourceGuid: source.resourceGuid,
            ),
        ],
      ),
    );
  });

  @override
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  ) => _read(() async {
    final result = await client.spocClassroomTranscript(
      subId: subId,
      resourceGuid: resourceGuid,
    );
    return (
      route: result.route,
      data: ClassroomTranscript(
        segments: [
          for (final segment in result.data.segments)
            ClassroomTranscriptSegment(
              beginMs: segment.beginMs.toInt(),
              endMs: segment.endMs.toInt(),
              text: segment.text,
            ),
        ],
      ),
    );
  });

  @override
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  ) => _read(() async {
    final result = await client.spocClassroomSummary(
      subId: subId,
      resourceGuid: resourceGuid,
    );
    final summary = result.data;
    return (
      route: result.route,
      data: ClassroomSummary(
        summary: summary.summary,
        keywords: summary.keywords,
        qa: [
          for (final item in summary.qa)
            ClassroomQuestion(
              question: item.question,
              answer: item.answer,
              startMs: item.startMs.toInt(),
            ),
        ],
        chapters: [
          for (final item in summary.chapters)
            ClassroomChapter(
              startMs: item.startMs.toInt(),
              endMs: item.endMs.toInt(),
              headline: item.headline,
              summary: item.summary,
            ),
        ],
      ),
    );
  });

  @override
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  ) => _read(() async {
    final result = await client.spocClassroomSlides(
      courseId: courseId,
      subId: subId,
      resourceGuid: resourceGuid,
    );
    return (
      route: result.route,
      data: ClassroomSlides(
        slides: [
          for (final slide in result.data.slides)
            ClassroomSlide(
              offsetMs: slide.offsetMs.toInt(),
              imageUrl: slide.imageUrl,
              thumbUrl: slide.thumbUrl,
            ),
        ],
      ),
    );
  });
}

ClassroomStatus _status(BridgeClassroomStatus status) => switch (status) {
  BridgeClassroomStatus.live => ClassroomStatus.live,
  BridgeClassroomStatus.replay => ClassroomStatus.replay,
  BridgeClassroomStatus.noReplay => ClassroomStatus.noReplay,
  BridgeClassroomStatus.upcoming => ClassroomStatus.upcoming,
  BridgeClassroomStatus.tencentMeeting => ClassroomStatus.tencentMeeting,
  BridgeClassroomStatus.other => ClassroomStatus.other,
};
