import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'projection.dart' show bridgeMapYgdkRecordsResult, bridgeYgdkHomeRecords;
import '../../support/mapping.dart'
    show bridgeCacheTime, bridgeToConnectionMode, bridgeTypedErrorCode;
part 'cache_records.dart';
part 'cache_home.dart';

final class HomeYgdkRead {
  const HomeYgdkRead(
    this.data,
    this.route, {
    this.state,
    this.cache,
    this.account,
  });
  final BridgeYgdkOverview data;
  final BridgeConnectionMode route;
  final BridgeHomeRefreshState? state;
  final BridgeOfflineCache? cache;
  final LocalAccount? account;
}
