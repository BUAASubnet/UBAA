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
) async {
  final canonicalInput = validateYgdkSubmitInput(input);
  return _prepareIntent(
    backend,
    backend.client.prepareYgdkSubmit(
      request: BridgeYgdkSubmitRequest(
        target: BridgeYgdkSubmitTarget(
          classifyId: canonicalInput.action.classifyId,
          itemId: canonicalInput.action.itemId,
        ),
        startTime: canonicalInput.startTime,
        endTime: canonicalInput.endTime,
        place: canonicalInput.place,
        shareToSquare: canonicalInput.shareToSquare,
        photo: BridgePhotoUpload(
          bytes: Uint8List.fromList(canonicalInput.photo.bytes),
          fileName: canonicalInput.photo.fileName,
          mimeType: canonicalInput.photo.mimeType,
        ),
      ),
    ),
  );
}

Future<WriteIntent> _prepareCgyySubmitReservation(
  BridgeBackend backend,
  CgyySubmitInput input,
) async {
  final validated = validateCgyySubmitInput(input);
  final actions = validated.actions.toList(growable: false)
    ..sort((left, right) => left.timeOrdinal.compareTo(right.timeOrdinal));
  final target = actions.first;
  return _prepareIntent(
    backend,
    backend.client.prepareCgyySubmitReservation(
      request: BridgeCgyySubmitReservationRequest(
        venueSiteId: target.venueSiteId,
        reservationDate: target.reservationDate,
        selections: actions
            .map(
              (action) => BridgeCgyyReservationSelection(
                spaceId: action.spaceId,
                timeId: action.timeId,
                venueSpaceGroupId: action.venueSpaceGroupId,
              ),
            )
            .toList(growable: false),
        phone: validated.phone,
        theme: validated.theme,
        purposeType: validated.purposeType,
        joinerNum: validated.joinerNum,
        activityContent: validated.activityContent,
        joiners: validated.joiners,
        isPhilosophySocialSciences: validated.isPhilosophySocialSciences,
        isOffSchoolJoiner: validated.isOffSchoolJoiner,
      ),
    ),
  );
}

Future<WriteIntent> _prepareCgyyCancelOrder(
  BridgeBackend backend, {
  required int id,
}) async {
  if (id <= 0) throw const BackendException(UbaaErrorCode.invalidInput);
  final intent = await _prepareIntent(
    backend,
    backend.client.prepareCgyyCancelOrder(
      request: BridgeCgyyCancelOrderRequest(orderId: id),
    ),
  );
  return intent.withReadbackQuery(
    FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: id),
  );
}

Future<WriteIntent> _prepareEvaluationSubmitCourses(
  BridgeBackend backend,
  List<EvaluationSubmitTarget> targets,
) => _prepareIntent(
  backend,
  backend.client.prepareEvaluationSubmitCourses(
    request: BridgeEvaluationSubmitCoursesRequest(
      targets: targets
          .map(
            (target) => BridgeEvaluationSubmitTarget(
              rwid: target.rwid,
              wjid: target.wjid,
              kcdm: target.kcdm,
              bpdm: target.bpdm,
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
