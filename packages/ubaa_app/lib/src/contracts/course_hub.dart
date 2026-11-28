import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class CourseHubBackend {
  set onAcademicIdentity(void Function(bool?)? listener);
  Future<List<CourseHubWeek>> courseHubWeeks(
    String account,
    ConnectionMode route,
    String term,
  );
  Future<List<String>> courseHubOverrides(String account, String term);
  Future<void> saveCourseHubLink(
    String account,
    String term,
    String courseId,
    bool linked,
  );
}
