import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 展示资料独立于认证身份；本地和在线使用相同字段。
abstract interface class ProfileCacheBackend {
  Future<OfflineProfileRead> readCachedProfile(RoutePolicy policy);
  Future<ProfileRefresh> refreshProfile({required LocalAccount account});
}

final class OfflineProfileRead {
  const OfflineProfileRead(this.profile, {this.error});
  final CachedProfile? profile;
  final BackendException? error;
}

final class CachedProfile {
  const CachedProfile({
    required this.accountId,
    required this.route,
    required this.fetchedAt,
    required this.complete,
    required this.profile,
  });
  final String accountId;
  final UserSummary profile;
  final ConnectionMode route;
  final DateTime fetchedAt;
  final bool complete;
  UserSummary toDisplay() => profileDisplay(
    profile,
    DataEvidence(
      accountId: accountId,
      origin: DataOrigin.persisted,
      fetchedAt: fetchedAt,
      complete: complete,
      savedForOffline: true,
    ),
    route,
  );
}

final class ProfileRefresh {
  const ProfileRefresh({
    required this.profile,
    required this.route,
    required this.evidence,
  });
  final UserSummary profile;
  final ConnectionMode route;
  final DataEvidence evidence;
  UserSummary toDisplay() => profileDisplay(profile, evidence, route);
}

/// 展示副本的构造不回写认证身份。
UserSummary profileDisplay(
  UserSummary profile,
  DataEvidence? evidence,
  ConnectionMode? route, {
  String? notice,
  String? accountScope,
}) => UserSummary(
  username: profile.username,
  displayName: profile.displayName,
  department: profile.department,
  schoolId: profile.schoolId,
  email: profile.email,
  phone: profile.phone,
  idCardTypeName: profile.idCardTypeName,
  profileEvidence: evidence,
  profileRoute: route,
  profileNotice: notice,
  accountScope: accountScope ?? evidence?.accountId ?? profile.accountScope,
);
