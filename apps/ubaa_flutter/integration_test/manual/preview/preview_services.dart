part of 'preview_backend.dart';

/// 预览读模型由复用夹具与本次运行的内存状态共同生成。
extension _PreviewServices on PreviewBackend {
  FeatureResult _boya(FeatureQuery q) {
    final base = boyaData(q, state, selections: selections);
    if (q.view != FeatureQueryView.bykcChosenCourses) return base;
    final rows = <FeatureDetail>[];
    final ids = {
      for (final d in base.details)
        (d.presentation as BykcChosenPresentation).courseId,
      for (final e in selections.entries)
        if (e.value) e.key,
    };
    for (final id in ids) {
      if (selections[id] == false) continue;
      final detail = boyaData(
        FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '$id'),
        state,
        selections: selections,
      ).details.first;
      final p = detail.presentation as BykcCoursePresentation;
      if (p.status != BykcCourseStatus.selected) continue;
      rows.add(
        FeatureDetail(
          title: p.courseName,
          presentation: BykcChosenPresentation(
            recordId: 9000 + id,
            courseId: id,
            courseName: p.courseName,
            courseTeacher: '合成教师',
            coursePosition: '合成报告厅',
            courseStartDate: '${previewDay(DateTime.now())} 14:00:00',
            courseEndDate: '${previewDay(DateTime.now())} 16:00:00',
            checkin: signedCourses[id] ?? 5,
            fullDetail: q.courseId == '$id' ? p : null,
          ),
          actions: [
            BykcDeselectAction(
              courseId: id,
              eligibility: ActionEligibility.allowed,
            ),
            BykcSignAction(
              courseId: id,
              kind: BykcSignKind.signIn,
              eligibility: ActionEligibility.allowed,
              requiresCoordinates: false,
            ),
            BykcSignAction(
              courseId: id,
              kind: BykcSignKind.signOut,
              eligibility: ActionEligibility.allowed,
              requiresCoordinates: false,
            ),
          ],
        ),
      );
    }
    return FeatureResult.success(
      details: rows,
      overview: base.overview,
      resolvedRoute: ConnectionMode.direct,
    );
  }

  FeatureResult _result(
    List<FeatureDetail> rows, {
    FeaturePagination? pagination,
  }) => FeatureResult.success(
    details: rows,
    pagination: pagination,
    resolvedRoute: ConnectionMode.direct,
  );
  FeatureResult _rooms(FeatureQuery q) {
    if (q.view == FeatureQueryView.cgyyLockCode) {
      return _result([
        const FeatureDetail(
          title: '合成门锁',
          presentation: CgyyLockPresentation(available: true),
        ),
      ]);
    }
    if (q.view == FeatureQueryView.cgyyOrders ||
        q.view == FeatureQueryView.cgyyOrderDetail) {
      final seeds = roomData(
        const FeatureQuery(
          view: FeatureQueryView.cgyyOrders,
          page: 0,
          size: 100,
        ),
        state,
      ).details.map((d) => d.presentation as CgyyOrderPresentation);
      final all = [...roomOrders, ...seeds]
          .where(
            (p) =>
                q.view != FeatureQueryView.cgyyOrderDetail || p.id == q.orderId,
          )
          .map((p) {
            final cancelled =
                cancelledRooms.contains(p.id) || p.orderStatus == 2;
            return FeatureDetail(
              title: '合成研讨室预约',
              presentation: CgyyOrderPresentation(
                id: p.id,
                venueSiteId: p.venueSiteId,
                reservationDate: p.reservationDate,
                venueName: p.venueName,
                venueSpaceName: p.venueSpaceName,
                theme: p.theme,
                reservationStartDate: p.reservationStartDate,
                reservationEndDate: p.reservationEndDate,
                orderStatus: cancelled ? 2 : 1,
                checkStatus: 1,
                statusText: cancelled ? '已取消' : '预约成功',
              ),
              readNavigation: q.view == FeatureQueryView.cgyyOrderDetail
                  ? null
                  : FeatureReadNavigation(
                      feature: FeatureId.cgyy,
                      query: FeatureQuery(
                        view: FeatureQueryView.cgyyOrderDetail,
                        orderId: p.id,
                      ),
                    ),
              actions: [
                CgyyCancelAction(
                  orderId: p.id,
                  orderStatus: cancelled ? 2 : 1,
                  checkStatus: 1,
                  targetOrderId: cancelled ? null : p.id,
                  cancelledTargetOrderId: cancelled ? p.id : null,
                  eligibility: cancelled
                      ? ActionEligibility.denied
                      : ActionEligibility.allowed,
                ),
              ],
            );
          })
          .toList();
      if (q.view == FeatureQueryView.cgyyOrderDetail) return _result(all);
      final page = q.page < 0 ? 0 : q.page;
      return _result(
        all.skip(page * q.size).take(q.size).toList(),
        pagination: FeaturePagination(
          page: page + 1,
          size: q.size,
          total: all.length,
          hasMore: (page + 1) * q.size < all.length,
        ),
      );
    }
    final result = roomData(q.copyWith(date: q.date ?? DateTime.now()), state);
    return _result(
      result.details.map((d) {
        final p = d.presentation;
        if (p is! CgyyDayPresentation) return d;
        return FeatureDetail(
          title: d.title,
          presentation: CgyyDayPresentation(
            venueSiteId: p.venueSiteId,
            reservationDate: p.reservationDate,
            availableDates: [
              for (var i = 0; i < 7; i++)
                previewDay(DateTime.now().add(Duration(days: i))),
            ],
            timeSlots: p.timeSlots,
            spaces: p.spaces,
            reservationTotalNum: p.reservationTotalNum,
          ),
        );
      }).toList(),
    );
  }

  FeatureResult _library(FeatureQuery q) {
    if (q.view == FeatureQueryView.libbookBookings) {
      final seeds = libraryData(
        const FeatureQuery(view: FeatureQueryView.libbookBookings, size: 100),
        'normal',
      ).details.map((d) => d.presentation as LibbookBookingPresentation);
      final all = [...seatBookings, ...seeds].map((p) {
        final cancelled = cancelledSeats.contains(p.id);
        return FeatureDetail(
          title: p.name,
          presentation: LibbookBookingPresentation(
            id: p.id,
            name: p.name,
            areaName: p.areaName,
            seatNumber: p.seatNumber,
            day: p.day,
            beginTime: p.beginTime,
            endTime: p.endTime,
            status: cancelled ? 6 : p.status,
            statusName: cancelled ? '已取消' : p.statusName,
          ),
          actions: [
            LibbookCancelAction(
              bookingId: p.id,
              page: q.page <= 0 ? 1 : q.page,
              limit: q.size,
              eligibility: cancelled || p.status != 1
                  ? ActionEligibility.denied
                  : ActionEligibility.allowed,
            ),
          ],
        );
      }).toList();
      final page = q.page <= 0 ? 1 : q.page;
      return _result(
        all.skip((page - 1) * q.size).take(q.size).toList(),
        pagination: FeaturePagination(
          page: page,
          size: q.size,
          total: all.length,
          hasMore: page * q.size < all.length,
        ),
      );
    }
    final base = libraryData(q.copyWith(date: q.date ?? DateTime.now()), state);
    return _result(
      base.details.map((d) {
        final p = d.presentation;
        if (p is! LibbookAreaSchedulePresentation) return d;
        return FeatureDetail(
          title: d.title,
          presentation: LibbookAreaSchedulePresentation(
            id: p.id,
            name: p.name,
            days: [
              for (var i = 0; i < 3; i++)
                LibbookDaySchedulePresentation(
                  day: previewDay(DateTime.now().add(Duration(days: i))),
                  timeSlots: p.days.first.timeSlots,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
