import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 课堂演示资料只用于页面与 Widget 测试，媒体地址不会连接外部服务。
final class DemoClassroomService implements ClassroomService, SpocFilesService {
  const DemoClassroomService();

  static const _kcid = 'fixture-classroom';
  static const _courseId = '101';
  static const _title = '课堂直录播演示';
  static const _replaySubId = '201';
  static const _teacherGuid = 'fixtureTeacher';
  static const _slidesGuid = 'fixtureSlides';
  static const _media = 'https://example.invalid';
  static const _schedule = [
    (_replaySubId, '第一周回放', 1, ClassroomStatus.replay),
    ('202', '第二周直播', 2, ClassroomStatus.live),
    ('203', '第三周无回放', 3, ClassroomStatus.noReplay),
    ('204', '第四周未开始', 4, ClassroomStatus.upcoming),
  ];

  ClassroomCatalog get _catalog => ClassroomCatalog(
    courseId: _courseId,
    title: _title,
    teachers: const ['演示教师'],
    termName: '演示学期',
    sessions: [
      for (final (subId, title, week, status) in _schedule)
        ClassroomSessionSummary(
          subId: subId,
          title: title,
          week: week,
          startSecs: 1800000000 + week * 604800,
          endSecs: 1800003600 + week * 604800,
          room: '演示教室',
          lecturer: '演示教师',
          status: status,
        ),
    ],
  );

  @override
  Future<SpocRead<List<SpocCourse>>> courses() async => (
    data: const [SpocCourse(courseId: _kcid, name: _title, teacher: '演示教师')],
    route: ConnectionMode.direct,
  );

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) async {
    if (kcid != _kcid) throw const BackendException(UbaaErrorCode.invalidInput);
    return (data: _catalog, route: ConnectionMode.direct);
  }

  @override
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  ) async {
    if (courseId == _courseId) {
      for (final period in _catalog.sessions) {
        if (period.subId != subId) continue;
        return (
          route: ConnectionMode.direct,
          data: ClassroomSession(
            title: period.title,
            startSecs: period.startSecs,
            endSecs: period.endSecs,
            status: period.status,
            sources: switch (period.status) {
              ClassroomStatus.replay => const [
                ClassroomPlaybackSource(
                  kind: ClassroomPlaybackKind.teacher,
                  url: '$_media/teacher.mp4',
                  durationSecs: 3600,
                  timeOffsetSecs: 0,
                  resourceGuid: _teacherGuid,
                ),
                ClassroomPlaybackSource(
                  kind: ClassroomPlaybackKind.slides,
                  url: '$_media/slides.mp4',
                  durationSecs: 3480,
                  timeOffsetSecs: -120,
                  resourceGuid: _slidesGuid,
                ),
              ],
              ClassroomStatus.live => const [
                ClassroomPlaybackSource(
                  kind: ClassroomPlaybackKind.teacher,
                  url: '$_media/teacher.m3u8',
                ),
                ClassroomPlaybackSource(
                  kind: ClassroomPlaybackKind.student,
                  url: '$_media/student.m3u8',
                ),
              ],
              _ => const [],
            },
          ),
        );
      }
    }
    throw const BackendException(UbaaErrorCode.invalidInput);
  }

  void _requireReplay(String subId, String resourceGuid) {
    if (subId != _replaySubId ||
        resourceGuid != _teacherGuid && resourceGuid != _slidesGuid) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
  }

  @override
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  ) async {
    _requireReplay(subId, resourceGuid);
    return (
      route: ConnectionMode.direct,
      data: const ClassroomTranscript(
        segments: [
          ClassroomTranscriptSegment(
            beginMs: 0,
            endMs: 2600,
            text: '今天介绍课堂直录播的示例。',
          ),
          ClassroomTranscriptSegment(
            beginMs: 3000,
            endMs: 6100,
            text: '点击时间点可以跳到相应片段。',
          ),
        ],
      ),
    );
  }

  @override
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  ) async {
    _requireReplay(subId, resourceGuid);
    return (
      route: ConnectionMode.direct,
      data: const ClassroomSummary(
        summary: '本节展示课堂回放与资料时间轴。',
        keywords: ['回放', '时间轴'],
        qa: [
          ClassroomQuestion(
            question: '如何定位片段？',
            answer: '选择时间点。',
            startMs: 3000,
          ),
        ],
        chapters: [
          ClassroomChapter(
            startMs: 0,
            endMs: 6100,
            headline: '课堂介绍',
            summary: '演示资料的入口。',
          ),
        ],
      ),
    );
  }

  @override
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  ) async {
    if (courseId != _courseId) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    _requireReplay(subId, resourceGuid);
    return (
      route: ConnectionMode.direct,
      data: const ClassroomSlides(
        slides: [
          ClassroomSlide(
            offsetMs: 3000,
            imageUrl: '$_media/slide.png',
            thumbUrl: '$_media/slide-thumb.png',
          ),
        ],
      ),
    );
  }

  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) async => (data: const <SpocCourseFile>[], route: ConnectionMode.direct);

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  ) async => throw const BackendException(UbaaErrorCode.unsupported);

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  ) async => throw const BackendException(UbaaErrorCode.unsupported);
}
