import 'package:ubaa_domain/ubaa_domain.dart';

import '../contracts/backend.dart';

const _maxYgdkPhotoBytes = 10 * 1024 * 1024;

final RegExp _ygdkDateTimePattern = RegExp(
  r'^([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2})$',
);

/// 校验并复制阳光打卡输入；除地点外不得规范化原始字段。
YgdkSubmitInput validateYgdkSubmitInput(YgdkSubmitInput input) {
  final start = _parseYgdkLocalDateTime(input.startTime);
  final end = _parseYgdkLocalDateTime(input.endTime);
  final photo = input.photo;
  if (!input.action.hasCanonicalTarget ||
      start == null ||
      end == null ||
      start.year != end.year ||
      start.month != end.month ||
      start.day != end.day ||
      end.minuteOfDay <= start.minuteOfDay ||
      photo.bytes.isEmpty ||
      photo.bytes.length > _maxYgdkPhotoBytes ||
      photo.bytes.any((value) => value < 0 || value > 255) ||
      !_isValidYgdkPhotoFileName(photo.fileName) ||
      !_isValidYgdkPhotoMimeType(photo.mimeType)) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }

  final normalizedPlace = input.place?.trim();
  return YgdkSubmitInput(
    action: input.action,
    startTime: input.startTime,
    endTime: input.endTime,
    place: normalizedPlace == null || normalizedPlace.isEmpty
        ? null
        : normalizedPlace,
    shareToSquare: input.shareToSquare,
    photo: YgdkPhotoInput(
      bytes: List<int>.unmodifiable(photo.bytes),
      fileName: photo.fileName,
      mimeType: photo.mimeType,
    ),
  );
}

({int year, int month, int day, int minuteOfDay})? _parseYgdkLocalDateTime(
  String value,
) {
  final match = _ygdkDateTimePattern.firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final parsed = DateTime.utc(year, month, day, hour, minute);
  if (parsed.year != year ||
      parsed.month != month ||
      parsed.day != day ||
      parsed.hour != hour ||
      parsed.minute != minute) {
    return null;
  }
  return (
    year: year,
    month: month,
    day: day,
    minuteOfDay: hour * Duration.minutesPerHour + minute,
  );
}

bool _isValidYgdkPhotoFileName(String value) {
  final characters = value.runes;
  if (value != value.trim() ||
      value == '.' ||
      value == '..' ||
      characters.isEmpty ||
      characters.length > 128) {
    return false;
  }
  return !characters.any(
    (character) =>
        character == 0x2f ||
        character == 0x5c ||
        character == 0x22 ||
        character <= 0x1f ||
        (character >= 0x7f && character <= 0x9f),
  );
}

bool _isValidYgdkPhotoMimeType(String value) {
  if (value != value.trim() || !value.startsWith('image/')) return false;
  final subtype = value.substring('image/'.length);
  return subtype.isNotEmpty && subtype.codeUnits.every(_isHttpTokenCodeUnit);
}

bool _isHttpTokenCodeUnit(int value) =>
    (value >= 0x30 && value <= 0x39) ||
    (value >= 0x41 && value <= 0x5a) ||
    (value >= 0x61 && value <= 0x7a) ||
    const <int>{
      0x21,
      0x23,
      0x24,
      0x25,
      0x26,
      0x27,
      0x2a,
      0x2b,
      0x2d,
      0x2e,
      0x5e,
      0x5f,
      0x60,
      0x7c,
      0x7e,
    }.contains(value);
