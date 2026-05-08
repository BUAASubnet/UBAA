package cn.edu.ubaa.api.core

import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionRuntime
import cn.edu.ubaa.api.auth.AuthServiceBackend
import cn.edu.ubaa.api.auth.RelayAuthServiceBackend
import cn.edu.ubaa.api.auth.RelayUserServiceBackend
import cn.edu.ubaa.api.auth.UserServiceBackend
import cn.edu.ubaa.api.feature.BykcApiBackend
import cn.edu.ubaa.api.feature.CgyyApiBackend
import cn.edu.ubaa.api.feature.ClassroomApiBackend
import cn.edu.ubaa.api.feature.EvaluationServiceBackend
import cn.edu.ubaa.api.feature.GradeApiBackend
import cn.edu.ubaa.api.feature.JudgeApiBackend
import cn.edu.ubaa.api.feature.LibBookApiBackend
import cn.edu.ubaa.api.feature.RelayBykcApiBackend
import cn.edu.ubaa.api.feature.RelayCgyyApiBackend
import cn.edu.ubaa.api.feature.RelayClassroomApiBackend
import cn.edu.ubaa.api.feature.RelayEvaluationServiceBackend
import cn.edu.ubaa.api.feature.RelayGradeApiBackend
import cn.edu.ubaa.api.feature.RelayJudgeApiBackend
import cn.edu.ubaa.api.feature.RelayLibBookApiBackend
import cn.edu.ubaa.api.feature.RelayScheduleApiBackend
import cn.edu.ubaa.api.feature.RelaySigninApiBackend
import cn.edu.ubaa.api.feature.RelaySpocApiBackend
import cn.edu.ubaa.api.feature.RelayYgdkApiBackend
import cn.edu.ubaa.api.feature.ScheduleApiBackend
import cn.edu.ubaa.api.feature.SigninApiBackend
import cn.edu.ubaa.api.feature.SpocApiBackend
import cn.edu.ubaa.api.feature.YgdkApiBackend
import cn.edu.ubaa.api.local.LocalAuthServiceBackend
import cn.edu.ubaa.api.local.LocalBykcApiBackend
import cn.edu.ubaa.api.local.LocalCgyyApiBackend
import cn.edu.ubaa.api.local.LocalClassroomApiBackend
import cn.edu.ubaa.api.local.LocalEvaluationServiceBackend
import cn.edu.ubaa.api.local.LocalGradeApiBackend
import cn.edu.ubaa.api.local.LocalJudgeApiBackend
import cn.edu.ubaa.api.local.LocalLibBookApiBackend
import cn.edu.ubaa.api.local.LocalScheduleApiBackend
import cn.edu.ubaa.api.local.LocalSigninApiBackend
import cn.edu.ubaa.api.local.LocalSpocApiBackend
import cn.edu.ubaa.api.local.LocalUserServiceBackend
import cn.edu.ubaa.api.local.LocalYgdkApiBackend

interface ApiFactory {
  fun authService(): AuthServiceBackend

  fun userService(): UserServiceBackend

  fun scheduleApi(): ScheduleApiBackend

  fun signinApi(): SigninApiBackend

  fun spocApi(): SpocApiBackend

  fun judgeApi(): JudgeApiBackend

  fun bykcApi(): BykcApiBackend

  fun cgyyApi(): CgyyApiBackend

  fun ygdkApi(): YgdkApiBackend

  fun classroomApi(): ClassroomApiBackend

  fun evaluationService(): EvaluationServiceBackend

  fun gradeApi(): GradeApiBackend

  fun libBookApi(): LibBookApiBackend
}

internal object DefaultApiFactory : ApiFactory {
  private val directBackends = LocalBackendSet()
  private val webVpnBackends = LocalBackendSet()

  private fun mode(): ConnectionMode =
      ConnectionRuntime.currentMode() ?: ConnectionMode.SERVER_RELAY

  fun clearCachedBackends() {
    directBackends.clearCache()
    webVpnBackends.clearCache()
  }

  override fun authService(): AuthServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).authService
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).authService
        ConnectionMode.SERVER_RELAY -> RelayAuthServiceBackend()
      }

  override fun userService(): UserServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).userService
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).userService
        ConnectionMode.SERVER_RELAY -> RelayUserServiceBackend()
      }

  override fun scheduleApi(): ScheduleApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).scheduleApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).scheduleApi
        ConnectionMode.SERVER_RELAY -> RelayScheduleApiBackend()
      }

  override fun signinApi(): SigninApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).signinApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).signinApi
        ConnectionMode.SERVER_RELAY -> RelaySigninApiBackend()
      }

  override fun spocApi(): SpocApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).spocApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).spocApi
        ConnectionMode.SERVER_RELAY -> RelaySpocApiBackend()
      }

  override fun judgeApi(): JudgeApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).judgeApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).judgeApi
        ConnectionMode.SERVER_RELAY -> RelayJudgeApiBackend()
      }

  override fun bykcApi(): BykcApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).bykcApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).bykcApi
        ConnectionMode.SERVER_RELAY -> RelayBykcApiBackend()
      }

  override fun cgyyApi(): CgyyApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).cgyyApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).cgyyApi
        ConnectionMode.SERVER_RELAY -> RelayCgyyApiBackend()
      }

  override fun ygdkApi(): YgdkApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).ygdkApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).ygdkApi
        ConnectionMode.SERVER_RELAY -> RelayYgdkApiBackend()
      }

  override fun classroomApi(): ClassroomApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).classroomApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).classroomApi
        ConnectionMode.SERVER_RELAY -> RelayClassroomApiBackend()
      }

  override fun evaluationService(): EvaluationServiceBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).evaluationService
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).evaluationService
        ConnectionMode.SERVER_RELAY -> RelayEvaluationServiceBackend()
      }

  override fun gradeApi(): GradeApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).gradeApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).gradeApi
        ConnectionMode.SERVER_RELAY -> RelayGradeApiBackend()
      }

  override fun libBookApi(): LibBookApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> localBackends(ConnectionMode.DIRECT).libBookApi
        ConnectionMode.WEBVPN -> localBackends(ConnectionMode.WEBVPN).libBookApi
        ConnectionMode.SERVER_RELAY -> RelayLibBookApiBackend()
      }

  private fun localBackends(mode: ConnectionMode): LocalBackendSet =
      when (mode) {
        ConnectionMode.DIRECT -> directBackends
        ConnectionMode.WEBVPN -> webVpnBackends
        ConnectionMode.SERVER_RELAY -> error("Server relay mode does not use local backends")
      }

  private class LocalBackendSet {
    val authService = LocalAuthServiceBackend()
    val userService = LocalUserServiceBackend()
    val scheduleApi = LocalScheduleApiBackend()
    val signinApi = LocalSigninApiBackend()
    val spocApi = LocalSpocApiBackend()
    val judgeApi = LocalJudgeApiBackend()
    val bykcApi = LocalBykcApiBackend()
    val cgyyApi = LocalCgyyApiBackend()
    val ygdkApi = LocalYgdkApiBackend()
    val classroomApi = LocalClassroomApiBackend()
    val evaluationService = LocalEvaluationServiceBackend()
    val gradeApi = LocalGradeApiBackend()
    val libBookApi = LocalLibBookApiBackend()

    fun clearCache() {
      signinApi.clearCache()
      spocApi.clearCache()
      judgeApi.clearCache()
      bykcApi.clearCache()
      cgyyApi.clearCache()
      ygdkApi.clearCache()
      classroomApi.clearCache()
      evaluationService.clearCache()
      libBookApi.clearCache()
    }
  }
}

internal object RelayApiFactory : ApiFactory {
  override fun authService(): AuthServiceBackend = RelayAuthServiceBackend()

  override fun userService(): UserServiceBackend = RelayUserServiceBackend()

  override fun scheduleApi(): ScheduleApiBackend = RelayScheduleApiBackend()

  override fun signinApi(): SigninApiBackend = RelaySigninApiBackend()

  override fun spocApi(): SpocApiBackend = RelaySpocApiBackend()

  override fun judgeApi(): JudgeApiBackend = RelayJudgeApiBackend()

  override fun bykcApi(): BykcApiBackend = RelayBykcApiBackend()

  override fun cgyyApi(): CgyyApiBackend = RelayCgyyApiBackend()

  override fun ygdkApi(): YgdkApiBackend = RelayYgdkApiBackend()

  override fun classroomApi(): ClassroomApiBackend = RelayClassroomApiBackend()

  override fun evaluationService(): EvaluationServiceBackend = RelayEvaluationServiceBackend()

  override fun gradeApi(): GradeApiBackend = RelayGradeApiBackend()

  override fun libBookApi(): LibBookApiBackend = RelayLibBookApiBackend()
}
