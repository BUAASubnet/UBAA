part of 'projection.dart';

String bridgeSigninCacheDate(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value))
    throw const BackendException(UbaaErrorCode.internalError);
  return '${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6)}';
}
