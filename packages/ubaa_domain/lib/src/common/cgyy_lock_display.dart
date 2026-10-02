import 'dart:async';

/// 专用页面短期材料，不进入FeatureResult、JSON、缓存或诊断。
class CgyyLockDisplay {
  CgyyLockDisplay({
    this.code,
    this.dueDate,
    this.reservationReference,
    this.venueName,
    this.siteName,
    this.spaceName,
    this.orderName,
    this.reservationDate,
    this.reservationDateDetail,
    this.reservationStartDate,
    this.reservationEndDate,
  });
  String? code;
  String? dueDate;
  String? reservationReference;
  String? venueName;
  String? siteName;
  String? spaceName;
  String? orderName;
  String? reservationDate;
  String? reservationDateDetail;
  String? reservationStartDate;
  String? reservationEndDate;
  bool get hasReservation =>
      reservationReference != null ||
      reservationDate != null ||
      reservationStartDate != null;
  String? get venueText {
    final parts = [venueName, siteName].whereType<String>();
    return parts.isEmpty ? null : parts.join(' ');
  }

  String? get timeRangeText {
    var value = reservationDateDetail;
    if (value == null) return null;
    for (final label in [spaceName, siteName].whereType<String>()) {
      if (value.startsWith(label))
        return value
            .substring(label.length)
            .replaceFirst(RegExp(r'^[ /\->]+'), '');
    }
    return value;
  }

  void release() {
    code = null;
    dueDate = null;
    reservationReference = null;
    venueName = null;
    siteName = null;
    spaceName = null;
    orderName = null;
    reservationDate = null;
    reservationDateDetail = null;
    reservationStartDate = null;
    reservationEndDate = null;
  }

  @override
  String toString() => 'CgyyLockDisplay([REDACTED])';
}

abstract interface class CgyyLockDisplaySession {
  Stream<void> get cancelled;
  Future<CgyyLockDisplay> read();
  void cancel();
}
