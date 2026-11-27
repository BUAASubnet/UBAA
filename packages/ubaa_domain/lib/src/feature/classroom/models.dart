import '../../common/route.dart';

enum ClassroomStatus { live, replay, noReplay, upcoming, tencentMeeting, other }

enum ClassroomPlaybackKind { teacher, slides, student }

final class ClassroomCatalog {
  const ClassroomCatalog({
    required this.courseId,
    required this.title,
    required this.teachers,
    required this.termName,
    required this.sessions,
  });

  /// 智学北航的课程标识；与课程列表中的 SPOC `kcid` 不同。
  final String courseId;
  final String title, termName;
  final List<String> teachers;
  final List<ClassroomSessionSummary> sessions;
}

final class ClassroomSessionSummary {
  const ClassroomSessionSummary({
    required this.subId,
    required this.title,
    this.week,
    required this.startSecs,
    required this.endSecs,
    required this.room,
    required this.lecturer,
    required this.status,
  });

  final String subId, title, room, lecturer;
  final int? week;
  final int startSecs, endSecs;
  final ClassroomStatus status;
}

final class ClassroomSession {
  const ClassroomSession({
    required this.title,
    required this.startSecs,
    required this.endSecs,
    required this.status,
    required this.sources,
  });

  final String title;
  final int startSecs, endSecs;
  final ClassroomStatus status;
  final List<ClassroomPlaybackSource> sources;
}

final class ClassroomPlaybackSource {
  const ClassroomPlaybackSource({
    required this.kind,
    required this.url,
    this.durationSecs,
    this.timeOffsetSecs,
    this.resourceGuid,
  });

  final ClassroomPlaybackKind kind;
  final String url;
  final int? durationSecs, timeOffsetSecs;
  final String? resourceGuid;
}

final class ClassroomTranscript {
  const ClassroomTranscript({required this.segments});
  final List<ClassroomTranscriptSegment> segments;
}

final class ClassroomTranscriptSegment {
  const ClassroomTranscriptSegment({
    required this.beginMs,
    required this.endMs,
    required this.text,
  });

  final int beginMs, endMs;
  final String text;
}

final class ClassroomSummary {
  const ClassroomSummary({
    this.summary,
    required this.keywords,
    required this.qa,
    required this.chapters,
  });

  final String? summary;
  final List<String> keywords;
  final List<ClassroomQuestion> qa;
  final List<ClassroomChapter> chapters;
}

final class ClassroomQuestion {
  const ClassroomQuestion({
    required this.question,
    required this.answer,
    required this.startMs,
  });

  final String question, answer;
  final int startMs;
}

final class ClassroomChapter {
  const ClassroomChapter({
    required this.startMs,
    required this.endMs,
    required this.headline,
    required this.summary,
  });

  final int startMs, endMs;
  final String headline, summary;
}

final class ClassroomSlides {
  const ClassroomSlides({required this.slides});
  final List<ClassroomSlide> slides;
}

final class ClassroomSlide {
  const ClassroomSlide({
    required this.offsetMs,
    required this.imageUrl,
    required this.thumbUrl,
  });

  final int offsetMs;
  final String imageUrl, thumbUrl;
}

typedef ClassroomRead<T> = ({T data, ConnectionMode route});

/// 页面内发起的课堂在线读取，返回各次读取的实际路线。
abstract interface class ClassroomService {
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid);
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  );
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  );
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  );
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  );
}
