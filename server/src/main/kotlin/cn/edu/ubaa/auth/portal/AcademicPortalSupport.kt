package cn.edu.ubaa.auth

internal suspend fun ensureUndergradPortalAccess(
    sessionManager: SessionManager,
    username: String,
    session: SessionManager.UserSession,
    graduateUnsupportedMessage: String,
    unavailableExceptionFactory: () -> Exception,
    warmupCoordinator: AcademicPortalWarmupCoordinator =
        GlobalAcademicPortalWarmupCoordinator.instance,
) {
  when (session.portalType) {
    AcademicPortalType.UNDERGRAD -> return
    AcademicPortalType.GRADUATE ->
        throw UnsupportedAcademicPortalException(graduateUnsupportedMessage)
    AcademicPortalType.UNKNOWN -> {
      when (val result = warmupCoordinator.awaitOrStart(username, session.client)) {
        AcademicPortalProbeResult.UNDERGRAD_READY -> {
          sessionManager.updateSessionPortalType(username, AcademicPortalType.UNDERGRAD)
          return
        }
        AcademicPortalProbeResult.GRADUATE_READY -> {
          sessionManager.updateSessionPortalType(username, AcademicPortalType.GRADUATE)
          throw UnsupportedAcademicPortalException(graduateUnsupportedMessage)
        }
        AcademicPortalProbeResult.SSO_REQUIRED -> {
          sessionManager.invalidateSession(username)
          throw LoginException("BYXT session expired")
        }
        AcademicPortalProbeResult.UNAVAILABLE -> throw unavailableExceptionFactory()
      }
    }
  }
}
