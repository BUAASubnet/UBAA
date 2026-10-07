part of 'mapping.dart';

DateTime bridgeCacheTime(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
