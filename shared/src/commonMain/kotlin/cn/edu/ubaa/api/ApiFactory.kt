package cn.edu.ubaa.api

interface ApiFactory {
  fun authService(): AuthServiceBackend

  fun userService(): UserServiceBackend

  fun scheduleApi(): ScheduleApiBackend

  fun signinApi(): SigninApiBackend

  fun spocApi(): SpocApiBackend

  fun bykcApi(): BykcApiBackend

  fun cgyyApi(): CgyyApiBackend

  fun ygdkApi(): YgdkApiBackend

  fun classroomApi(): ClassroomApiBackend

  fun evaluationService(): EvaluationServiceBackend

  fun gradeApi(): GradeApiBackend
}

internal object DefaultApiFactory : ApiFactory {
  private fun mode(): ConnectionMode =
      ConnectionRuntime.currentMode() ?: ConnectionMode.SERVER_RELAY

  override fun authService(): AuthServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalAuthServiceBackend()
        ConnectionMode.WEBVPN -> LocalAuthServiceBackend()
        ConnectionMode.SERVER_RELAY -> RelayAuthServiceBackend()
      }

  override fun userService(): UserServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalUserServiceBackend()
        ConnectionMode.WEBVPN -> LocalUserServiceBackend()
        ConnectionMode.SERVER_RELAY -> RelayUserServiceBackend()
      }

  override fun scheduleApi(): ScheduleApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalScheduleApiBackend()
        ConnectionMode.WEBVPN -> LocalScheduleApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayScheduleApiBackend()
      }

  override fun signinApi(): SigninApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalSigninApiBackend()
        ConnectionMode.WEBVPN -> LocalSigninApiBackend()
        ConnectionMode.SERVER_RELAY -> RelaySigninApiBackend()
      }

  override fun spocApi(): SpocApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalSpocApiBackend()
        ConnectionMode.WEBVPN -> LocalSpocApiBackend()
        ConnectionMode.SERVER_RELAY -> RelaySpocApiBackend()
      }

  override fun bykcApi(): BykcApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalBykcApiBackend()
        ConnectionMode.WEBVPN -> LocalBykcApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayBykcApiBackend()
      }

  override fun cgyyApi(): CgyyApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalCgyyApiBackend()
        ConnectionMode.WEBVPN -> LocalCgyyApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayCgyyApiBackend()
      }

  override fun ygdkApi(): YgdkApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalYgdkApiBackend()
        ConnectionMode.WEBVPN -> LocalYgdkApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayYgdkApiBackend()
      }

  override fun classroomApi(): ClassroomApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalClassroomApiBackend()
        ConnectionMode.WEBVPN -> LocalClassroomApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayClassroomApiBackend()
      }

  override fun evaluationService(): EvaluationServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalEvaluationServiceBackend()
        ConnectionMode.WEBVPN -> LocalEvaluationServiceBackend()
        ConnectionMode.SERVER_RELAY -> RelayEvaluationServiceBackend()
      }

  override fun gradeApi(): GradeApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalGradeApiBackend()
        ConnectionMode.WEBVPN -> LocalGradeApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayGradeApiBackend()
      }
}

internal object RelayApiFactory : ApiFactory {
  override fun authService(): AuthServiceBackend = RelayAuthServiceBackend()

  override fun userService(): UserServiceBackend = RelayUserServiceBackend()

  override fun scheduleApi(): ScheduleApiBackend = RelayScheduleApiBackend()

  override fun signinApi(): SigninApiBackend = RelaySigninApiBackend()

  override fun spocApi(): SpocApiBackend = RelaySpocApiBackend()

  override fun bykcApi(): BykcApiBackend = RelayBykcApiBackend()

  override fun cgyyApi(): CgyyApiBackend = RelayCgyyApiBackend()

  override fun ygdkApi(): YgdkApiBackend = RelayYgdkApiBackend()

  override fun classroomApi(): ClassroomApiBackend = RelayClassroomApiBackend()

  override fun evaluationService(): EvaluationServiceBackend = RelayEvaluationServiceBackend()

  override fun gradeApi(): GradeApiBackend = RelayGradeApiBackend()
}
