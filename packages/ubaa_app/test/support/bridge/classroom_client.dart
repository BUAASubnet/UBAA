import 'package:ubaa_bindings/ubaa_bindings.dart';

import 'fixtures.dart' show currentBridgeContractVersion;
import 'recording_client.dart';

class ClassroomRecordingClient extends FixtureCharacterizationBridgeClient {
  BridgeError? classroomError;

  @override
  int contractVersion() => currentBridgeContractVersion;

  @override
  Future<BridgeRoutedClassroomCatalog> spocClassroomCatalog({
    required String kcid,
  }) async {
    calls.add('catalog:$kcid');
    if (classroomError case final error?) throw error;
    return BridgeRoutedClassroomCatalog(
      route: fixtureWebVpnRoute,
      data: BridgeClassroomCatalog(
        courseId: '101',
        title: '合成课堂',
        teachers: const ['合成教师'],
        termName: '合成学期',
        sessions: [
          for (final status in BridgeClassroomStatus.values)
            BridgeClassroomSessionSummary(
              subId: '102',
              title: '合成节次',
              week: 3,
              startSecs: 10,
              endSecs: 20,
              room: '合成教室',
              lecturer: '合成讲师',
              status: status,
            ),
        ],
      ),
    );
  }

  @override
  Future<BridgeRoutedClassroomSession> spocClassroomSession({
    required String courseId,
    required String subId,
  }) async {
    calls.add('session:$courseId:$subId');
    return BridgeRoutedClassroomSession(
      route: fixtureWebVpnRoute,
      data: BridgeClassroomSession(
        title: '合成回放',
        startSecs: 10,
        endSecs: 20,
        status: BridgeClassroomStatus.replay,
        sources: [
          BridgeClassroomPlaybackSource(
            kind: BridgeClassroomPlaybackKind.teacher,
            url: 'https://example.invalid/fixture.mp4',
            durationSecs: BigInt.from(120),
            timeOffsetSecs: -12,
            resourceGuid: 'fixture123',
          ),
          const BridgeClassroomPlaybackSource(
            kind: BridgeClassroomPlaybackKind.slides,
            url: 'https://example.invalid/slides.mp4',
          ),
          const BridgeClassroomPlaybackSource(
            kind: BridgeClassroomPlaybackKind.student,
            url: 'https://example.invalid/live.m3u8',
          ),
        ],
      ),
    );
  }

  @override
  Future<BridgeRoutedClassroomTranscript> spocClassroomTranscript({
    required String subId,
    required String resourceGuid,
  }) async {
    calls.add('transcript:$subId:$resourceGuid');
    return BridgeRoutedClassroomTranscript(
      route: fixtureWebVpnRoute,
      data: BridgeClassroomTranscript(
        segments: [
          BridgeClassroomTranscriptSegment(
            beginMs: BigInt.from(125),
            endMs: BigInt.from(500),
            text: '合成转写',
          ),
        ],
      ),
    );
  }

  @override
  Future<BridgeRoutedClassroomSummary> spocClassroomSummary({
    required String subId,
    required String resourceGuid,
  }) async {
    calls.add('summary:$subId:$resourceGuid');
    return BridgeRoutedClassroomSummary(
      route: fixtureWebVpnRoute,
      data: BridgeClassroomSummary(
        summary: '合成摘要',
        keywords: const ['关键词'],
        qa: [
          BridgeClassroomQuestion(
            question: '提问',
            answer: '回答',
            startMs: BigInt.from(125),
          ),
        ],
        chapters: [
          BridgeClassroomChapter(
            startMs: BigInt.from(125),
            endMs: BigInt.from(500),
            headline: '章节',
            summary: '简介',
          ),
        ],
      ),
    );
  }

  @override
  Future<BridgeRoutedClassroomSlides> spocClassroomSlides({
    required String courseId,
    required String subId,
    required String resourceGuid,
  }) async {
    calls.add('slides:$courseId:$subId:$resourceGuid');
    return BridgeRoutedClassroomSlides(
      route: fixtureWebVpnRoute,
      data: BridgeClassroomSlides(
        slides: [
          BridgeClassroomSlide(
            offsetMs: BigInt.from(500),
            imageUrl: 'https://example.invalid/slide.png',
            thumbUrl: 'https://example.invalid/thumb.png',
          ),
        ],
      ),
    );
  }
}
