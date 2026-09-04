part of '../bridge_backend.dart';

Future<WriteIntent> _prepareBykcSelectCourse(
  BridgeBackend backend, {
  required int courseId,
}) => _prepareIntent(
  backend,
  backend.client.prepareBykcSelectCourse(
    request: BridgeBykcCourseRequest(courseId: courseId),
  ),
);

Future<WriteIntent> _prepareBykcDeselectCourse(
  BridgeBackend backend, {
  required int courseId,
}) => _prepareIntent(
  backend,
  backend.client.prepareBykcDeselectCourse(
    request: BridgeBykcCourseRequest(courseId: courseId),
  ),
);

Future<WriteIntent> _prepareBykcSignCourse(
  BridgeBackend backend, {
  required int courseId,
  double? lat,
  double? lng,
  required int signType,
}) => _prepareIntent(
  backend,
  backend.client.prepareBykcSignCourse(
    request: BridgeBykcSignCourseRequest(
      courseId: courseId,
      lat: lat,
      lng: lng,
      signType: signType,
    ),
  ),
);

Future<WriteIntent> _prepareSigninPerform(
  BridgeBackend backend, {
  required String courseId,
}) => _prepareIntent(
  backend,
  backend.client.prepareSigninPerform(
    request: BridgeSigninPerformRequest(courseId: courseId),
  ),
);

Future<WriteIntent> _prepareLibbookReserve(
  BridgeBackend backend, {
  required String areaId,
  required String seatId,
  required String day,
  required String segment,
  required String startTime,
  required String endTime,
}) => _prepareIntent(
  backend,
  backend.client.prepareLibbookReserve(
    request: BridgeLibbookReserveRequest(
      areaId: areaId,
      seatId: seatId,
      day: day,
      segment: segment,
      startTime: startTime,
      endTime: endTime,
    ),
  ),
);

Future<WriteIntent> _prepareLibbookCancelBooking(
  BridgeBackend backend, {
  required String id,
  required int page,
  required int limit,
}) async {
  final intent = await _prepareIntent(
    backend,
    backend.client.prepareLibbookCancelBooking(
      request: BridgeLibbookCancelBookingRequest(
        id: id,
        page: page,
        limit: limit,
      ),
    ),
  );
  return intent.withReadbackQuery(
    FeatureQuery(
      view: FeatureQueryView.libbookBookings,
      page: page,
      size: limit,
    ),
  );
}

Future<WriteIntent> _prepareYgdkSubmit(
  BridgeBackend backend,
  YgdkSubmitInput input,
) => _prepareIntent(
  backend,
  backend.client.prepareYgdkSubmit(
    request: BridgeYgdkSubmitRequest(
      itemId: input.itemId,
      startTime: input.startTime,
      endTime: input.endTime,
      place: input.place,
      shareToSquare: input.shareToSquare,
      photo: input.photo == null
          ? null
          : BridgePhotoUpload(
              bytes: Uint8List.fromList(input.photo!.bytes),
              fileName: input.photo!.fileName,
              mimeType: input.photo!.mimeType,
            ),
    ),
  ),
);

Future<WriteIntent> _prepareCgyySubmitReservation(
  BridgeBackend backend,
  CgyySubmitInput input,
) => _prepareIntent(
  backend,
  backend.client.prepareCgyySubmitReservation(
    request: BridgeCgyySubmitReservationRequest(
      venueSiteId: input.venueSiteId,
      reservationDate: input.reservationDate,
      selections: input.selections
          .map(
            (selection) => BridgeCgyyReservationSelection(
              spaceId: selection.spaceId,
              timeId: selection.timeId,
              venueSpaceGroupId: selection.venueSpaceGroupId,
            ),
          )
          .toList(growable: false),
      phone: input.phone,
      theme: input.theme,
      purposeType: input.purposeType,
      joinerNum: input.joinerNum,
      activityContent: input.activityContent,
      joiners: input.joiners,
      isPhilosophySocialSciences: input.isPhilosophySocialSciences,
      isOffSchoolJoiner: input.isOffSchoolJoiner,
    ),
  ),
);

Future<WriteIntent> _prepareCgyyCancelOrder(
  BridgeBackend backend, {
  required int id,
}) => _prepareIntent(
  backend,
  backend.client.prepareCgyyCancelOrder(
    request: BridgeCgyyCancelOrderRequest(id: id),
  ),
);

Future<WriteIntent> _prepareEvaluationSubmitCourses(
  BridgeBackend backend,
  List<EvaluationCourseInput> courses,
) => _prepareIntent(
  backend,
  backend.client.prepareEvaluationSubmitCourses(
    request: BridgeEvaluationSubmitCoursesRequest(
      courses: courses
          .map(
            (course) => BridgeEvaluationCourse(
              id: course.id,
              kcmc: course.kcmc,
              bpmc: course.bpmc,
              isEvaluated: course.isEvaluated,
              rwid: course.rwid,
              wjid: course.wjid,
              kcdm: course.kcdm,
              bpdm: course.bpdm,
              pjrdm: course.pjrdm,
              pjrmc: course.pjrmc,
              xnxq: course.xnxq,
              msid: course.msid,
              zdmc: course.zdmc,
              ypjcs: course.ypjcs,
              xypjcs: course.xypjcs,
              sxz: course.sxz,
              rwh: course.rwh,
              xn: course.xn,
              xq: course.xq,
              pjlxid: course.pjlxid,
              sfksqbpj: course.sfksqbpj,
              yxsfktjst: course.yxsfktjst,
            ),
          )
          .toList(growable: false),
    ),
  ),
);

Future<WriteIntent> _prepareIntent(
  BridgeBackend backend,
  Future<BridgeWriteIntent> pending,
) async {
  try {
    return _mapIntent(await pending);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}
