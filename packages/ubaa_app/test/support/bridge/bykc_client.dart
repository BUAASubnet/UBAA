import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'recording_client.dart' show fixtureWebVpnRoute;

dynamic fixtureBykcCatalogRead(
  Invocation invocation, {
  required bool emptyReads,
}) {
  final named = invocation.namedArguments;
  switch (invocation.memberName) {
    case #bykcCourseFullDetail:
      return Future.value(
        const BridgeRoutedBykcCourseFullDetail(
          route: fixtureWebVpnRoute,
          data: BridgeBykcCourseFullDetail(
            course: BridgeBykcCourseCatalogItem(
              course: BridgeBykcCourse(
                id: 42,
                courseName: '课程详情',
                status: BridgeBykcCourseStatus.available,
                selectEligibility: BridgeActionEligibility.denied,
                deselectEligibility: BridgeActionEligibility.allowed,
              ),
              audienceCampuses: [],
              hasSignPoints: false,
            ),
            audienceColleges: [],
            audienceTerms: [],
            audienceGroups: [],
          ),
        ),
      );
    case #bykcCourseCatalog:
      return Future.value(
        BridgeRoutedBykcCourseCatalog(
          route: fixtureWebVpnRoute,
          data: BridgeBykcCourseCatalogPage(
            content: emptyReads
                ? const []
                : const [
                    BridgeBykcCourseCatalogItem(
                      course: BridgeBykcCourse(
                        id: 101,
                        courseName: '课程分页',
                        status: BridgeBykcCourseStatus.available,
                        selectEligibility: BridgeActionEligibility.allowed,
                        deselectEligibility: BridgeActionEligibility.denied,
                      ),
                      audienceCampuses: [],
                      hasSignPoints: false,
                    ),
                  ],
            totalElements: emptyReads ? 0 : 201,
            totalPages: emptyReads ? 0 : 3,
            size: named[#size] as int,
            number: named[#page] as int,
          ),
        ),
      );
    default:
      throw StateError('意外的博雅合成读取');
  }
}
