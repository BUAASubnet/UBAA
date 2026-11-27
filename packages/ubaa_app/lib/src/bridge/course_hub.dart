import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../contracts/course_hub.dart';
import '../contracts/backend.dart';
import 'cache/lifecycle.dart';
import 'context.dart';
import 'features/academic/projection.dart';
import 'support/mapping.dart';

mixin BridgeCourseHub implements CourseHubBackend {
  BridgeContext get courseHubContext;
  @override
  set onAcademicIdentity(void Function(bool?)? listener) =>
      courseHubContext.onAcademicIdentity = listener;

  Future<T> _courseHubLocal<T>(
    String account,
    Future<T> Function(BridgeOfflineCache) read,
  ) => bridgeWithOfflineRead(courseHubContext, () async {
    if (courseHubContext.client.contractVersion() < 86)
      throw const BackendException(UbaaErrorCode.unsupported);
    await bridgeAwaitOfflineScope(courseHubContext);
    try {
      return await read(bridgeManagementCache(courseHubContext, account));
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  });

  @override
  Future<List<CourseHubWeek>> courseHubWeeks(
    String account,
    ConnectionMode route,
    String term,
  ) => _courseHubLocal(
    account,
    (cache) async => [
      for (final entry in await cache.courseHubSchedule(
        route: bridgeToBridgeConnectionMode(route),
        term: term,
      ))
        CourseHubWeek(
          startDate: entry.week.startDate,
          endDate: entry.week.endDate,
          slots: entry.schedule.arrangedList
              .map(bridgeMapScheduleCourseDetail)
              .toList(),
        ),
    ],
  );
  @override
  Future<List<String>> courseHubOverrides(String account, String term) =>
      _courseHubLocal(account, (cache) => cache.readJudgeOverrides(term: term));
  @override
  Future<void> saveCourseHubLink(
    String account,
    String term,
    String courseId,
    bool linked,
  ) => _courseHubLocal(
    account,
    (cache) =>
        cache.setJudgeLink(term: term, courseId: courseId, linked: linked),
  );
}
