import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 本地遮罩与在线完整资料分别返回；遮罩字段不能用作登录身份。
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
    this.maskedUsername,
    this.maskedName,
    this.maskedSchoolId,
  });
  final String accountId;
  final String? maskedUsername, maskedName, maskedSchoolId;
  final ConnectionMode route;
  final DateTime fetchedAt;
  final bool complete;
  UserSummary toDisplay() => UserSummary(
    username: maskedUsername ?? maskedSchoolId ?? '本机账号',
    displayName: maskedName,
    schoolId: maskedSchoolId,
    profileRoute: route,
    accountScope: accountId,
    profileEvidence: DataEvidence(
      accountId: accountId,
      origin: DataOrigin.persisted,
      fetchedAt: fetchedAt,
      complete: complete,
      savedForOffline: true,
    ),
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
