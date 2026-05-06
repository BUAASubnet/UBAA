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
import cn.edu.ubaa.api.feature.RelayBykcApiBackend
import cn.edu.ubaa.api.feature.RelayCgyyApiBackend
import cn.edu.ubaa.api.feature.RelayClassroomApiBackend
import cn.edu.ubaa.api.feature.RelayEvaluationServiceBackend
import cn.edu.ubaa.api.feature.RelayGradeApiBackend
import cn.edu.ubaa.api.feature.RelayJudgeApiBackend
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

  override fun judgeApi(): JudgeApiBackend =
      when (mode()) {
        ConnectionMode.DIRECT -> LocalJudgeApiBackend()
        ConnectionMode.WEBVPN -> LocalJudgeApiBackend()
        ConnectionMode.SERVER_RELAY -> RelayJudgeApiBackend()
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

  override fun judgeApi(): JudgeApiBackend = RelayJudgeApiBackend()

  override fun bykcApi(): BykcApiBackend = RelayBykcApiBackend()

  override fun cgyyApi(): CgyyApiBackend = RelayCgyyApiBackend()

  override fun ygdkApi(): YgdkApiBackend = RelayYgdkApiBackend()

  override fun classroomApi(): ClassroomApiBackend = RelayClassroomApiBackend()

  override fun evaluationService(): EvaluationServiceBackend = RelayEvaluationServiceBackend()

  override fun gradeApi(): GradeApiBackend = RelayGradeApiBackend()
}
