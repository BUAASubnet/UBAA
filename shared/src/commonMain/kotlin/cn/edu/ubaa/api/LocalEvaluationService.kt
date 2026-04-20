package cn.edu.ubaa.api

import cn.edu.ubaa.model.evaluation.EvaluationCourse
import cn.edu.ubaa.model.evaluation.EvaluationCoursesResponse
import cn.edu.ubaa.model.evaluation.EvaluationProgress
import cn.edu.ubaa.model.evaluation.EvaluationResult
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import kotlin.random.Random
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

internal class LocalEvaluationServiceBackend : EvaluationServiceBackend {
  private val json = Json { ignoreUnknownKeys = true }
  private val emptyResponse =
      EvaluationCoursesResponse(
          courses = emptyList(),
          progress = EvaluationProgress(0, 0, 0),
      )

  override suspend fun getAllEvaluations(): Result<EvaluationCoursesResponse> =
      runLocalEvaluationCall("评教列表加载失败，请稍后重试") {
        if (!activateEvaluationSession()) {
          return@runLocalEvaluationCall emptyResponse
        }

        val xnxq = fetchCurrentXnxq() ?: return@runLocalEvaluationCall emptyResponse
        val tasks = fetchTasks()
        val courseMap = linkedMapOf<String, EvaluationCourse>()

        tasks.forEach { task ->
          fetchQuestionnaires(task.rwid).forEach { questionnaire ->
            val msid = questionnaire.msid?.takeIf { it.isNotBlank() } ?: "1"
            mergeCourses(
                courseMap = courseMap,
                courses = fetchCourses(task.rwid, questionnaire.wjid, xnxq, msid, sfyp = "0"),
                rwid = task.rwid,
                wjid = questionnaire.wjid,
                xnxq = xnxq,
                msid = msid,
                isEvaluated = false,
            )
            mergeCourses(
                courseMap = courseMap,
                courses = fetchCourses(task.rwid, questionnaire.wjid, xnxq, msid, sfyp = "1"),
                rwid = task.rwid,
                wjid = questionnaire.wjid,
                xnxq = xnxq,
                msid = msid,
                isEvaluated = true,
            )
          }
        }

        val courses = courseMap.values.sortedBy { it.isEvaluated }
        val pendingCount = courses.count { !it.isEvaluated }
        val evaluatedCount = courses.count { it.isEvaluated }
        EvaluationCoursesResponse(
            courses = courses,
            progress =
                EvaluationProgress(
                    totalCourses = courses.size,
                    evaluatedCourses = evaluatedCount,
                    pendingCourses = pendingCount,
                ),
        )
      }

  override suspend fun submitEvaluations(courses: List<EvaluationCourse>): List<EvaluationResult> {
    if (courses.isEmpty()) return emptyList()
    val authSession =
        LocalAuthSessionStore.get()
            ?: return courses.map { course ->
              EvaluationResult(
                  success = false,
                  message = localUnauthenticatedApiException().message ?: "登录状态已失效，请重新登录",
                  courseName = course.kcmc,
              )
            }

    return try {
      if (!activateEvaluationSession()) {
        return courses.map { course -> EvaluationResult(false, "评教提交失败，请稍后重试", course.kcmc) }
      }

      courses.map { course ->
        try {
          submitSingleEvaluation(course)
        } catch (e: LocalEvaluationAuthenticationException) {
          val failure = resolveLocalBusinessAuthenticationFailure("evaluation_error")
          EvaluationResult(
              success = false,
              message = failure.message ?: "评教服务暂时不可用，请稍后重试",
              courseName = course.kcmc,
          )
        } catch (e: Exception) {
          EvaluationResult(
              success = false,
              message = e.toUserFacingApiException("评教提交失败，请稍后重试").message ?: "评教提交失败，请稍后重试",
              courseName = course.kcmc,
          )
        }
      }
    } catch (e: LocalEvaluationAuthenticationException) {
      val failure = resolveLocalBusinessAuthenticationFailure("evaluation_error")
      courses.map { course ->
        EvaluationResult(
            success = false,
            message = failure.message ?: "评教服务暂时不可用，请稍后重试",
            courseName = course.kcmc,
        )
      }
    } catch (e: Exception) {
      val message = e.toUserFacingApiException("评教提交失败，请稍后重试").message ?: "评教提交失败，请稍后重试"
      courses.map { course -> EvaluationResult(false, message, course.kcmc) }
    }
  }

  private suspend fun submitSingleEvaluation(course: EvaluationCourse): EvaluationResult {
    reviseQuestionnairePattern(course.rwid, course.wjid, course.msid)
    val topic =
        fetchQuestionnaireTopic(course) ?: return EvaluationResult(false, "无法获取问卷题目", course.kcmc)
    val payload = buildEvaluationPayload(course, topic)
    if (payload.isEmpty()) {
      return EvaluationResult(false, "问卷没有题目", course.kcmc)
    }

    val response = submitEvaluation(payload)
    return if (response?.isSuccess() == true) {
      EvaluationResult(true, "评教成功", course.kcmc)
    } else {
      val code = response?.codeString() ?: "no-code"
      val message = response?.message ?: response?.msg ?: "提交失败，可能已评教"
      EvaluationResult(false, "提交失败(code=$code): $message", course.kcmc)
    }
  }

  private suspend fun activateEvaluationSession(): Boolean {
    return try {
      val response =
          LocalUpstreamClientProvider.shared()
              .get(localUpstreamUrl("https://spoc.buaa.edu.cn/pjxt/cas"))
      val body = response.bodyAsText()
      if (isLocalEvaluationSessionExpired(response, body)) {
        throw LocalEvaluationAuthenticationException()
      }
      response.status.value in 200..299
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      false
    }
  }

  private suspend fun fetchCurrentXnxq(): String? {
    return try {
      val response =
          LocalUpstreamClientProvider.shared()
              .post(localUpstreamUrl("https://spoc.buaa.edu.cn/pjxt/component/queryXnxq"))
      val envelope = decodeEnvelope<List<JsonObject>>(response)
      val first = envelope.content?.firstOrNull() ?: return null
      val xn = first.string("xn").orEmpty()
      val xq = first.string("xq").orEmpty()
      if (xn.isBlank() || xq.isBlank()) null else "$xn$xq"
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      null
    }
  }

  private suspend fun fetchTasks(): List<LocalEvaluationTask> {
    return try {
      val authSession =
          LocalAuthSessionStore.get() ?: throw LocalEvaluationAuthenticationException()
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks"
              )
          ) {
            parameter("yhdm", authSession.user.schoolid.ifBlank { authSession.username })
            parameter("rwmc", "")
            parameter("sfyp", "0")
            parameter("pageNum", "1")
            parameter("pageSize", "10")
          }
      decodeEnvelope<LocalEvaluationPage<LocalEvaluationTask>>(response).result?.list.orEmpty()
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      emptyList()
    }
  }

  private suspend fun fetchQuestionnaires(rwid: String): List<LocalEvaluationQuestionnaire> {
    return try {
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask"
              )
          ) {
            parameter("rwid", rwid)
            parameter("sfyp", "0")
            parameter("pageNum", "1")
            parameter("pageSize", "999")
          }
      decodeEnvelope<List<LocalEvaluationQuestionnaire>>(response).result.orEmpty()
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      emptyList()
    }
  }

  private suspend fun fetchCourses(
      rwid: String,
      wjid: String,
      xnxq: String,
      msid: String,
      sfyp: String,
  ): List<JsonObject> {
    return try {
      reviseQuestionnairePattern(rwid, wjid, msid)
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData"
              )
          ) {
            parameter("sfyp", sfyp)
            parameter("wjid", wjid)
            parameter("xnxq", xnxq)
            parameter("pageNum", "1")
            parameter("pageSize", "999")
          }
      decodeEnvelope<List<JsonObject>>(response).result.orEmpty()
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      emptyList()
    }
  }

  private suspend fun reviseQuestionnairePattern(rwid: String, wjid: String, msid: String = "1") {
    try {
      val response =
          LocalUpstreamClientProvider.shared().post(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/reviseQuestionnairePattern"
              )
          ) {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                      put("rwid", rwid)
                      put("wjid", wjid)
                      put("msid", msid)
                    }
                    .toString()
            )
          }
      decodeEnvelope<JsonElement>(response)
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      // Keep parity with the server implementation: mode switching failure should not
      // immediately abort subsequent fetches.
    }
  }

  private suspend fun fetchQuestionnaireTopic(course: EvaluationCourse): JsonObject? {
    return try {
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireTopic"
              )
          ) {
            parameter("id", "")
            parameter("rwid", course.rwid)
            parameter("wjid", course.wjid)
            parameter("zdmc", course.zdmc ?: "STID")
            parameter("ypjcs", course.ypjcs ?: 0)
            parameter("xypjcs", course.xypjcs ?: 1)
            parameter("sxz", course.sxz ?: "")
            parameter("pjrdm", course.pjrdm ?: "")
            parameter("pjrmc", course.pjrmc ?: "")
            parameter("bpdm", course.bpdm ?: "")
            parameter("bpmc", course.bpmc)
            parameter("kcdm", course.kcdm)
            parameter("kcmc", course.kcmc)
            parameter("rwh", course.rwh ?: "")
            parameter("xn", course.xn ?: "")
            parameter("xq", course.xq ?: "")
            parameter("xnxq", course.xnxq ?: "")
            parameter("pjlxid", course.pjlxid ?: "2")
            parameter("sfksqbpj", course.sfksqbpj ?: "1")
            parameter("yxsfktjst", course.yxsfktjst ?: "")
            parameter("yxdm", "")
          }
      decodeEnvelope<List<JsonObject>>(response).result?.firstOrNull()
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      null
    }
  }

  private suspend fun submitEvaluation(
      pjjglist: List<JsonObject>
  ): LocalEvaluationEnvelope<JsonElement>? {
    return try {
      val response =
          LocalUpstreamClientProvider.shared().post(
              localUpstreamUrl(
                  "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/submitSaveEvaluation"
              )
          ) {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                      putJsonArray("pjidlist") {}
                      putJsonArray("pjjglist") { pjjglist.forEach { add(it) } }
                      put("pjzt", "1")
                    }
                    .toString()
            )
          }
      decodeEnvelope<JsonElement>(response)
    } catch (e: LocalEvaluationAuthenticationException) {
      throw e
    } catch (_: Exception) {
      null
    }
  }

  private fun buildEvaluationPayload(
      course: EvaluationCourse,
      topic: JsonObject,
  ): List<JsonObject> {
    val questionnaireEntity = topic["pjxtWjWjbReturnEntity"]?.jsonObjectOrNull()
    val sections = questionnaireEntity?.get("wjzblist")?.jsonArray ?: JsonArray(emptyList())
    val questions = mutableListOf<JsonObject>()
    sections.forEach { section ->
      section.jsonObjectOrNull()?.get("tklist")?.jsonArray?.forEach { question ->
        question.jsonObjectOrNull()?.let { questions += it }
      }
    }
    if (questions.isEmpty()) return emptyList()

    val randomIndex = Random.nextInt(questions.size)
    val pjjgckb = topic["pjxtPjjgPjjgckb"]?.jsonArray ?: JsonArray(emptyList())
    val pjmap = topic["pjmap"]

    return pjjgckb.mapNotNull { item ->
      val payload = item.jsonObjectOrNull() ?: return@mapNotNull null
      buildJsonObject {
        put("bprdm", payload["bprdm"] ?: JsonNull)
        put("bprmc", payload["bprmc"] ?: JsonNull)
        put("kcdm", payload["kcdm"] ?: JsonNull)
        put("kcmc", payload["kcmc"] ?: JsonNull)
        put("pjdf", 93)
        put("pjfs", payload["pjfs"] ?: JsonPrimitive("1"))
        put("pjid", payload["pjid"] ?: JsonNull)
        put("pjlx", payload["pjlx"] ?: JsonNull)
        put("pjmap", pjmap ?: JsonNull)
        put("pjrdm", payload["pjrdm"] ?: JsonNull)
        put("pjrjsdm", payload["pjrjsdm"] ?: JsonNull)
        put("pjrxm", payload["pjrxm"] ?: JsonNull)
        put("pjsx", 1)
        putJsonArray("pjxxlist") {
          questions.forEachIndexed { index, question ->
            add(buildQuestionAnswer(course, payload, question, index == randomIndex))
          }
        }
        put("rwh", payload["rwh"] ?: JsonNull)
        put("stzjid", "xx")
        put("wjid", course.wjid)
        put("wjssrwid", payload["wjssrwid"] ?: JsonNull)
        put("wtjjy", "")
        put("xhgs", JsonNull)
        put("xnxq", payload["xnxq"] ?: JsonNull)
        put("sfxxpj", payload["sfxxpj"] ?: JsonPrimitive("1"))
        put("sqzt", JsonNull)
        put("yxfz", JsonNull)
        put("zsxz", payload["pjrjsdm"] ?: JsonPrimitive(""))
        put("sfnm", "1")
      }
    }
  }

  private fun buildQuestionAnswer(
      course: EvaluationCourse,
      payload: JsonObject,
      question: JsonObject,
      useSecondOption: Boolean,
  ): JsonObject {
    val questionType = question.string("tmlx") ?: "1"
    val options = question["tmxxlist"]?.jsonArray ?: JsonArray(emptyList())
    val firstOptionId = options.firstOrNull()?.jsonObjectOrNull()?.get("tmxxid")
    val selectedOptionId =
        if (useSecondOption && options.size > 1) {
          options.getOrNull(1)?.jsonObjectOrNull()?.get("tmxxid")
        } else {
          firstOptionId
        }

    return buildJsonObject {
      put("sjly", "1")
      put("stlx", questionType)
      put("wjid", course.wjid)
      put("wjssrwid", payload["wjssrwid"] ?: JsonNull)
      if (questionType == "6") {
        put("wjstctid", firstOptionId ?: JsonPrimitive(""))
      } else {
        put("wjstctid", "")
      }
      put("wjstid", question["tmid"] ?: JsonNull)
      putJsonArray("xxdalist") { if (selectedOptionId != null) add(selectedOptionId) }
    }
  }

  private suspend fun <T> runLocalEvaluationCall(
      defaultMessage: String,
      block: suspend () -> T,
  ): Result<T> {
    if (LocalAuthSessionStore.get() == null) {
      return Result.failure(localUnauthenticatedApiException())
    }

    return try {
      Result.success(block())
    } catch (e: LocalEvaluationAuthenticationException) {
      Result.failure(resolveLocalBusinessAuthenticationFailure("evaluation_error"))
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }

  private suspend inline fun <reified T> decodeEnvelope(
      response: HttpResponse
  ): LocalEvaluationEnvelope<T> {
    val body = response.bodyAsText()
    if (isLocalEvaluationSessionExpired(response, body)) {
      throw LocalEvaluationAuthenticationException()
    }
    if (response.status.value !in 200..299) {
      throw localBusinessApiException(
          code = "evaluation_error",
          defaultMessage = "评教服务暂时不可用，请稍后重试",
          status = response.status,
      )
    }

    val envelope =
        runCatching { json.decodeFromString<LocalEvaluationEnvelope<T>>(body) }
            .getOrElse {
              throw ApiCallException(
                  "评教服务返回无法解析",
                  status = HttpStatusCode.BadGateway,
                  code = "evaluation_error",
              )
            }
    if (!envelope.isSuccess()) {
      throw ApiCallException(
          message = envelope.message ?: envelope.msg ?: "评教服务暂时不可用，请稍后重试",
          status = HttpStatusCode.BadGateway,
          code = "evaluation_error",
      )
    }
    return envelope
  }

  private fun mergeCourses(
      courseMap: MutableMap<String, EvaluationCourse>,
      courses: List<JsonObject>,
      rwid: String,
      wjid: String,
      xnxq: String,
      msid: String,
      isEvaluated: Boolean,
  ) {
    courses.forEach { course ->
      val kcdm = course.string("kcdm") ?: return@forEach
      val bpdm = course.string("bpdm")
      val key = "${rwid}_${wjid}_${kcdm}_${bpdm.orEmpty()}"
      val existing = courseMap[key]
      courseMap[key] =
          EvaluationCourse(
              id = key,
              kcmc = course.string("kcmc") ?: existing?.kcmc ?: "未知课程",
              bpmc = course.string("bpmc") ?: existing?.bpmc ?: "未知教师",
              isEvaluated = isEvaluated || existing?.isEvaluated == true,
              rwid = rwid,
              wjid = wjid,
              kcdm = kcdm,
              bpdm = bpdm ?: existing?.bpdm,
              pjrdm = course.string("pjrdm") ?: existing?.pjrdm,
              pjrmc = course.string("pjrmc") ?: existing?.pjrmc,
              xnxq = xnxq,
              msid = msid,
              zdmc = course.string("zdmc") ?: existing?.zdmc ?: "STID",
              ypjcs = course.int("ypjcs") ?: existing?.ypjcs ?: 0,
              xypjcs = course.int("xypjcs") ?: existing?.xypjcs ?: 1,
              sxz = course.string("sxz") ?: existing?.sxz,
              rwh = course.string("rwh") ?: existing?.rwh,
              xn = course.string("xn") ?: existing?.xn,
              xq = course.string("xq") ?: existing?.xq,
              pjlxid = course.string("pjlxid") ?: existing?.pjlxid ?: "2",
              sfksqbpj = course.string("sfksqbpj") ?: existing?.sfksqbpj ?: "1",
              yxsfktjst = course.string("yxsfktjst") ?: existing?.yxsfktjst,
          )
    }
  }
}

@Serializable
private data class LocalEvaluationEnvelope<T>(
    val code: JsonElement? = null,
    val result: T? = null,
    val content: T? = null,
    val message: String? = null,
    @SerialName("msg") val msg: String? = null,
)

@Serializable private data class LocalEvaluationPage<T>(val list: List<T> = emptyList())

@Serializable private data class LocalEvaluationTask(val rwid: String, val rwmc: String)

@Serializable
private data class LocalEvaluationQuestionnaire(
    val wjid: String,
    val wjmc: String,
    val rwmc: String? = null,
    val msid: String? = null,
)

private class LocalEvaluationAuthenticationException : Exception()

private fun JsonElement?.codeString(): String? {
  return when (this) {
    null -> null
    is JsonPrimitive -> if (isString) contentOrNull else intOrNull?.toString()
    else -> null
  }
}

private fun <T> LocalEvaluationEnvelope<T>.codeString(): String? = code.codeString()

private fun <T> LocalEvaluationEnvelope<T>.isSuccess(): Boolean {
  return when (codeString()?.lowercase()) {
    "200",
    "0",
    "success" -> true
    else -> false
  }
}

private fun JsonElement.jsonObjectOrNull(): JsonObject? = this as? JsonObject

private fun JsonObject.string(name: String): String? =
    this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

private fun JsonObject.int(name: String): Int? = this[name]?.jsonPrimitive?.intOrNull

private fun isLocalEvaluationSessionExpired(response: HttpResponse, body: String): Boolean {
  if (response.status == HttpStatusCode.Unauthorized) return true
  val finalUrl = response.call.request.url.toString()
  if (localIsSsoUrl(finalUrl)) return true
  val trimmed = body.trimStart()
  if (
      trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
          trimmed.startsWith("<html", ignoreCase = true)
  ) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}
