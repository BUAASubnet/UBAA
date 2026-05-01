package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginPreloadResponse
import cn.edu.ubaa.model.evaluation.EvaluationCoursesResponse
import com.russhwolf.settings.MapSettings
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class ApiFactoryDispatchTest {
  @BeforeTest
  fun setup() {
    ConnectionRuntime.apiFactoryProvider = { RelayApiFactory }
    ConnectionModeStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
  }

  @AfterTest
  fun tearDown() {
    ConnectionRuntime.apiFactoryProvider = { RelayApiFactory }
    ConnectionRuntime.clearSelectedMode()
  }

  @Test
  fun `auth service default constructor delegates to connection runtime api factory`() = runTest {
    val backend = FakeAuthServiceBackend()
    ConnectionRuntime.apiFactoryProvider = {
      FakeApiFactory(
          authBackend = backend,
      )
    }

    val result = AuthService().preloadLoginState()

    assertTrue(result.isSuccess)
    assertEquals(1, backend.preloadCalls)
  }

  @Test
  fun `auth service created before mode selection resolves backend lazily from current mode`() =
      runTest {
        val relayBackend = FakeAuthServiceBackend()
        val localBackend = FakeAuthServiceBackend()
        ConnectionRuntime.apiFactoryProvider = {
          FakeApiFactory(
              authBackend =
                  when (ConnectionRuntime.currentMode()) {
                    ConnectionMode.DIRECT -> localBackend
                    else -> relayBackend
                  }
          )
        }

        val service = AuthService()

        ConnectionModeStore.save(ConnectionMode.DIRECT)
        ConnectionRuntime.resolveSelectedMode()

        val result = service.preloadLoginState()

        assertTrue(result.isSuccess)
        assertEquals(0, relayBackend.preloadCalls)
        assertEquals(1, localBackend.preloadCalls)
      }

  @Test
  fun `schedule api default constructor delegates to connection runtime api factory`() = runTest {
    val backend = FakeScheduleApiBackend()
    ConnectionRuntime.apiFactoryProvider = {
      FakeApiFactory(
          scheduleBackend = backend,
      )
    }

    val result = ScheduleApi().getTerms()

    assertTrue(result.isSuccess)
    assertEquals(1, backend.getTermsCalls)
  }

  @Test
  fun `grade api default constructor delegates to connection runtime api factory`() = runTest {
    val backend = FakeGradeApiBackend()
    ConnectionRuntime.apiFactoryProvider = {
      FakeApiFactory(
          gradeBackend = backend,
      )
    }

    val result = GradeApi().getGrades("2025-2026-1")

    assertTrue(result.isSuccess)
    assertEquals(1, backend.getGradesCalls)
  }

  @Test
  fun `schedule api created before mode selection resolves backend lazily from current mode`() =
      runTest {
        val relayBackend = FakeScheduleApiBackend()
        val localBackend = FakeScheduleApiBackend()
        ConnectionRuntime.apiFactoryProvider = {
          FakeApiFactory(
              scheduleBackend =
                  when (ConnectionRuntime.currentMode()) {
                    ConnectionMode.DIRECT -> localBackend
                    else -> relayBackend
                  }
          )
        }

        val api = ScheduleApi()

        ConnectionModeStore.save(ConnectionMode.DIRECT)
        ConnectionRuntime.resolveSelectedMode()

        val result = api.getTerms()

        assertTrue(result.isSuccess)
        assertEquals(0, relayBackend.getTermsCalls)
        assertEquals(1, localBackend.getTermsCalls)
      }

  @Test
  fun `evaluation service default constructor delegates to connection runtime api factory`() =
      runTest {
        val backend = FakeEvaluationServiceBackend()
        ConnectionRuntime.apiFactoryProvider = {
          FakeApiFactory(
              evaluationBackend = backend,
          )
        }

        val result = EvaluationService().getAllEvaluations()

        assertTrue(result.isSuccess)
        assertEquals(1, backend.getAllEvaluationsCalls)
      }

  @Test
  fun `default api factory routes webvpn supported services to local backends`() {
    ConnectionModeStore.save(ConnectionMode.WEBVPN)
    ConnectionRuntime.resolveSelectedMode()

    assertTrue(DefaultApiFactory.authService() is LocalAuthServiceBackend)
    assertTrue(DefaultApiFactory.userService() is LocalUserServiceBackend)
    assertTrue(DefaultApiFactory.scheduleApi() is LocalScheduleApiBackend)
    assertTrue(DefaultApiFactory.signinApi() is LocalSigninApiBackend)
    assertTrue(DefaultApiFactory.spocApi() is LocalSpocApiBackend)
    assertTrue(DefaultApiFactory.judgeApi() is LocalJudgeApiBackend)
    assertTrue(DefaultApiFactory.bykcApi() is LocalBykcApiBackend)
    assertTrue(DefaultApiFactory.cgyyApi() is LocalCgyyApiBackend)
    assertTrue(DefaultApiFactory.ygdkApi() is LocalYgdkApiBackend)
    assertTrue(DefaultApiFactory.classroomApi() is LocalClassroomApiBackend)
    assertTrue(DefaultApiFactory.evaluationService() is LocalEvaluationServiceBackend)
    assertTrue(DefaultApiFactory.gradeApi() is LocalGradeApiBackend)
  }
}

private class FakeApiFactory(
    private val authBackend: AuthServiceBackend = FakeAuthServiceBackend(),
    private val userBackend: UserServiceBackend = FakeUserServiceBackend(),
    private val scheduleBackend: ScheduleApiBackend = FakeScheduleApiBackend(),
    private val signinBackend: SigninApiBackend = FakeSigninApiBackend(),
    private val spocBackend: SpocApiBackend = FakeSpocApiBackend(),
    private val judgeBackend: JudgeApiBackend = FakeJudgeApiBackend(),
    private val bykcBackend: BykcApiBackend = FakeBykcApiBackend(),
    private val cgyyBackend: CgyyApiBackend = FakeCgyyApiBackend(),
    private val ygdkBackend: YgdkApiBackend = FakeYgdkApiBackend(),
    private val classroomBackend: ClassroomApiBackend = FakeClassroomApiBackend(),
    private val evaluationBackend: EvaluationServiceBackend = FakeEvaluationServiceBackend(),
    private val gradeBackend: GradeApiBackend = FakeGradeApiBackend(),
) : ApiFactory {
  override fun authService(): AuthServiceBackend = authBackend

  override fun userService(): UserServiceBackend = userBackend

  override fun scheduleApi(): ScheduleApiBackend = scheduleBackend

  override fun signinApi(): SigninApiBackend = signinBackend

  override fun spocApi(): SpocApiBackend = spocBackend

  override fun judgeApi(): JudgeApiBackend = judgeBackend

  override fun bykcApi(): BykcApiBackend = bykcBackend

  override fun cgyyApi(): CgyyApiBackend = cgyyBackend

  override fun ygdkApi(): YgdkApiBackend = ygdkBackend

  override fun classroomApi(): ClassroomApiBackend = classroomBackend

  override fun evaluationService(): EvaluationServiceBackend = evaluationBackend

  override fun gradeApi(): GradeApiBackend = gradeBackend
}

private class FakeAuthServiceBackend : AuthServiceBackend {
  var preloadCalls = 0
    private set

  override fun hasPersistedSession(): Boolean = false

  override fun applyStoredSession() = Unit

  override fun clearStoredSession() = Unit

  override suspend fun preloadLoginState(): Result<LoginPreloadResponse> {
    preloadCalls++
    return Result.success(
        LoginPreloadResponse(
            captchaRequired = true,
            captcha = CaptchaInfo(id = "captcha", imageUrl = "test"),
        )
    )
  }

  override suspend fun login(
      username: String,
      password: String,
      captcha: String?,
      execution: String?,
  ) = error("unused")

  override suspend fun getAuthStatus() = error("unused")

  override suspend fun logout(): Result<Unit> = Result.success(Unit)
}

private class FakeUserServiceBackend : UserServiceBackend {
  override suspend fun getUserInfo() = error("unused")
}

private class FakeScheduleApiBackend : ScheduleApiBackend {
  var getTermsCalls = 0
    private set

  override suspend fun getTerms(): Result<List<cn.edu.ubaa.model.dto.Term>> {
    getTermsCalls++
    return Result.success(emptyList())
  }

  override suspend fun getWeeks(termCode: String) = error("unused")

  override suspend fun getWeeklySchedule(termCode: String, week: Int) = error("unused")

  override suspend fun getTodaySchedule() = error("unused")

  override suspend fun getExamArrangement(termCode: String) = error("unused")
}

private class FakeGradeApiBackend : GradeApiBackend {
  var getGradesCalls = 0
    private set

  override suspend fun getGrades(termCode: String): Result<cn.edu.ubaa.model.dto.GradeData> {
    getGradesCalls++
    return Result.success(cn.edu.ubaa.model.dto.GradeData(termCode = termCode))
  }
}

private class FakeSigninApiBackend : SigninApiBackend {
  override suspend fun getTodayClasses() = error("unused")

  override suspend fun performSignin(courseId: String) = error("unused")
}

private class FakeSpocApiBackend : SpocApiBackend {
  override suspend fun getAssignments() = error("unused")

  override suspend fun getAssignmentDetail(assignmentId: String) = error("unused")
}

private class FakeJudgeApiBackend : JudgeApiBackend {
  override suspend fun getAssignments() = error("unused")

  override suspend fun getAssignmentDetail(courseId: String, assignmentId: String) =
      error("unused")
}

private class FakeBykcApiBackend : BykcApiBackend {
  override suspend fun getProfile() = error("unused")

  override suspend fun getCourses(page: Int, size: Int, all: Boolean) = error("unused")

  override suspend fun getCourseDetail(courseId: Long) = error("unused")

  override suspend fun getChosenCourses() = error("unused")

  override suspend fun getStatistics() = error("unused")

  override suspend fun selectCourse(courseId: Long) = error("unused")

  override suspend fun deselectCourse(courseId: Long) = error("unused")

  override suspend fun signCourse(courseId: Long, lat: Double?, lng: Double?, signType: Int) =
      error("unused")
}

private class FakeCgyyApiBackend : CgyyApiBackend {
  override suspend fun getVenueSites() = error("unused")

  override suspend fun getPurposeTypes() = error("unused")

  override suspend fun getDayInfo(venueSiteId: Int, date: String) = error("unused")

  override suspend fun submitReservation(
      request: cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
  ) = error("unused")

  override suspend fun getMyOrders(page: Int, size: Int) = error("unused")

  override suspend fun getOrderDetail(orderId: Int) = error("unused")

  override suspend fun cancelOrder(orderId: Int) = error("unused")

  override suspend fun getLockCode() = error("unused")
}

private class FakeYgdkApiBackend : YgdkApiBackend {
  override suspend fun getOverview() = error("unused")

  override suspend fun getRecords(page: Int, size: Int) = error("unused")

  override suspend fun submitClockin(request: cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest) =
      error("unused")
}

private class FakeClassroomApiBackend : ClassroomApiBackend {
  override suspend fun queryClassrooms(xqid: Int, date: String) = error("unused")
}

private class FakeEvaluationServiceBackend : EvaluationServiceBackend {
  var getAllEvaluationsCalls = 0
    private set

  override suspend fun getAllEvaluations(): Result<EvaluationCoursesResponse> {
    getAllEvaluationsCalls++
    return Result.success(
        EvaluationCoursesResponse(
            courses = emptyList(),
            progress = cn.edu.ubaa.model.evaluation.EvaluationProgress(0, 0, 0),
        )
    )
  }

  override suspend fun submitEvaluations(
      courses: List<cn.edu.ubaa.model.evaluation.EvaluationCourse>
  ) = emptyList<cn.edu.ubaa.model.evaluation.EvaluationResult>()
}
