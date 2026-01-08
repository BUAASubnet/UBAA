package cn.edu.ubaa.evaluation

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.slf4j.LoggerFactory

/** SPOC 系统 API 响应的通用包装结构。 */
@Serializable
data class SpocResult<T>(
        val code: JsonElement? = null,
        val result: T? = null,
        val content: T? = null,
        val message: String? = null,
        // 部分接口使用 msg 字段返回错误信息
        @kotlinx.serialization.SerialName("msg") val msg: String? = null
)

/** SPOC 系统分页数据包装结构。 */
@Serializable data class SpocPage<T>(val list: List<T>)

/** 评教任务数据结构。 */
@Serializable data class SpocTask(val rwid: String, val rwmc: String)

/** 问卷数据结构。 */
@Serializable
data class SpocQuestionnaire(
        val wjid: String,
        val wjmc: String,
        val rwmc: String? = null,
        val msid: String? = null
)

/** 待评教课程数据结构。 */
@Serializable
data class SpocCourse(
        val rwid: String,
        val wjid: String,
        val kcdm: String,
        val kcmc: String,
        val bpmc: String? = null,
        val bpdm: String? = null,
        val pjrdm: String? = null,
        val pjrmc: String? = null,
        val zdmc: String? = null,
        val ypjcs: Int? = null,
        val xypjcs: Int? = null,
        val sxz: String? = null,
        val rwh: String? = null,
        val xnxq: String? = null,
        val pjlxid: String? = null,
        val sfksqbpj: String? = null,
        val xn: String? = null,
        val xq: String? = null,
        val yxsfktjst: String? = null,
        val msid: String? = null
)

/**
 * 自动评教 SPOC 客户端。 封装了与 spoc.buaa.edu.cn 交互的底层 HTTP 请求。 负责处理 CAS 认证会话复用以及具体的评教业务 API 调用。
 *
 * @param username 用户学号，用于获取对应的 Session。
 * @param sessionManager 会话管理器，默认为全局单例。
 */
class EvaluationClient(
        private val username: String,
        private val sessionManager: SessionManager = GlobalSessionManager.instance
) {
    private val log = LoggerFactory.getLogger(EvaluationClient::class.java)
    private val baseUrl = "https://spoc.buaa.edu.cn/pjxt"
    private val json = Json { ignoreUnknownKeys = true }

    /** 获取当前用户的活跃 HttpClient 实例。 */
    private suspend fun getClient(): HttpClient = sessionManager.requireSession(username).client

    /**
     * 初始化评教系统会话。 通过访问 CAS 认证接口来激活或刷新当前 Session 在评教系统中的登录状态。
     *
     * @return 若会话初始化成功返回 true，否则返回 false。
     */
    suspend fun initSession(): Boolean {
        val resp = getClient().get("$baseUrl/cas")
        return resp.status.isSuccess()
    }

    /**
     * 检查用户是否有待评教的任务。
     *
     * 通过调用 queryDaiBan 接口来判断是否存在待评教任务。 这是一个关键的检查，确保用户确实有需要评教的课程：
     * - 如果用户已完成所有评教，该接口返回空列表，此时应返回 false
     * - 如果用户仍有待评教课程，该接口返回非空列表，此时返回 true
     *
     * @return 若有待评教任务返回 true，否则返回 false。
     */
    suspend fun hasPendingEvaluation(): Boolean {
        return try {
            val resp = getClient().post("$baseUrl/component/queryDaiBan").body<JsonElement>()
            // 响应应该是一个 JSON 数组，检查是否非空
            (resp as JsonArray).isNotEmpty()
        } catch (e: Exception) {
            log.error("Failed to check pending evaluation status", e)
            false
        }
    }

    /**
     * 获取当前学期代码（如 "2025-20261"）。
     *
     * @return 学期代码字符串，若获取失败返回 null。
     */
    suspend fun fetchCurrentXnxq(): String? {
        return try {
            val resp: SpocResult<List<JsonObject>> =
                    getClient().post("$baseUrl/component/queryXnxq").body()
            val first = resp.content?.firstOrNull() ?: return null
            val xn = first["xn"]?.toString()?.replace("\"", "") ?: ""
            val xq = first["xq"]?.toString()?.replace("\"", "") ?: ""
            "$xn$xq"
        } catch (e: Exception) {
            log.error("Failed to fetch xnxq", e)
            null
        }
    }

    /**
     * 获取用户的评教任务列表。
     *
     * @return 评教任务列表。
     */
    suspend fun fetchTasks(): List<SpocTask> {
        return try {
            val resp: SpocResult<SpocPage<SpocTask>> =
                    getClient()
                            .get(
                                    "$baseUrl/personnelEvaluation/listObtainPersonnelEvaluationTasks"
                            ) {
                                parameter("yhdm", username)
                                parameter("rwmc", "")
                                parameter("sfyp", "0")
                                parameter("pageNum", "1")
                                parameter("pageSize", "10")
                            }
                            .body()
            resp.result?.list ?: emptyList()
        } catch (e: Exception) {
            log.error("Failed to fetch tasks", e)
            emptyList()
        }
    }

    /**
     * 根据任务 ID 获取问卷列表。
     *
     * @param rwid 任务 ID。
     * @return 问卷列表。
     */
    suspend fun fetchQuestionnaires(rwid: String): List<SpocQuestionnaire> {
        return try {
            val resp: SpocResult<List<SpocQuestionnaire>> =
                    getClient()
                            .get("$baseUrl/evaluationMethodSix/getQuestionnaireListToTask") {
                                parameter("rwid", rwid)
                                parameter("sfyp", "0")
                                parameter("pageNum", "1")
                                parameter("pageSize", "999")
                            }
                            .body()
            resp.result ?: emptyList()
        } catch (e: Exception) {
            log.error("Failed to fetch questionnaires", e)
            emptyList()
        }
    }

    /**
     * 获取指定任务、问卷和学期下的**未评教**课程列表。
     *
     * 注意：参数 sfyp 控制过滤条件
     * - sfyp=0：只返回未评教的课程
     * - sfyp=1：只返回已评教的课程
     * - 调用前会自动切换问卷模式（reviseQuestionnairePattern）
     *
     * @param rwid 任务 ID。
     * @param wjid 问卷 ID。
     * @param xnxq 学期代码。
     * @param msid 模式 ID，可选。
     * @param sfyp 是否已评教，0=未评教，1=已评教。
     * @return 课程列表（根据 sfyp 参数过滤）。
     */
    suspend fun fetchCourses(
            rwid: String,
            wjid: String,
            xnxq: String,
            msid: String = "1",
            sfyp: String = "0"
    ): List<SpocCourse> {
        return try {
            // 切换模式 (Revise Questionnaire Pattern)
            reviseQuestionnairePattern(rwid, wjid, msid)

            val resp: SpocResult<List<SpocCourse>> =
                    getClient()
                            .get("$baseUrl/evaluationMethodSix/getRequiredReviewsData") {
                                parameter("sfyp", sfyp)
                                parameter("wjid", wjid)
                                parameter("xnxq", xnxq)
                                parameter("pageNum", "1")
                                parameter("pageSize", "999")
                            }
                            .body()
            resp.result?.map { it.copy(msid = msid) } ?: emptyList()
        } catch (e: Exception) {
            log.error("Failed to fetch courses (sfyp=$sfyp)", e)
            emptyList()
        }
    }

    /**
     * 切换问卷模式。 这是一个关键步骤，必须在获取问卷题目和提交评教前调用。 否则服务器会返回"问卷未开放"错误。
     *
     * @param rwid 任务 ID。
     * @param wjid 问卷 ID。
     * @param msid 模式 ID，默认为 "1"。
     */
    suspend fun reviseQuestionnairePattern(rwid: String, wjid: String, msid: String = "1") {
        try {
            getClient().post("$baseUrl/evaluationMethodSix/reviseQuestionnairePattern") {
                contentType(ContentType.Application.Json)
                setBody(
                        buildJsonObject {
                            put("rwid", rwid)
                            put("wjid", wjid)
                            put("msid", msid)
                        }
                )
            }
        } catch (e: Exception) {
            log.error("Failed to revise questionnaire pattern", e)
        }
    }

    /**
     * 获取特定课程的问卷题目详情。
     *
     * @param course 课程对象，包含获取题目所需的各项 ID 参数。
     * @return 题目详情的 JsonObject，若获取失败返回 null。
     */
    suspend fun fetchQuestionnaireTopic(course: SpocCourse): JsonObject? {
        return try {
            val resp: HttpResponse =
                    getClient().get("$baseUrl/evaluationMethodSix/getQuestionnaireTopic") {
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
                        parameter("bpmc", course.bpmc ?: "")
                        parameter("kcdm", course.kcdm ?: "")
                        parameter("kcmc", course.kcmc ?: "")
                        parameter("rwh", course.rwh ?: "")
                        parameter("xn", course.xn ?: "")
                        parameter("xq", course.xq ?: "")
                        parameter("xnxq", course.xnxq ?: "")
                        parameter("pjlxid", course.pjlxid ?: "2")
                        parameter("sfksqbpj", course.sfksqbpj ?: "1")
                        parameter("yxsfktjst", course.yxsfktjst ?: "")
                        parameter("yxdm", "")
                    }
            val data: SpocResult<List<JsonObject>> = resp.body()
            data.result?.firstOrNull()
        } catch (e: Exception) {
            log.error("Failed to fetch questionnaire topic", e)
            null
        }
    }

    /**
     * 提交评教结果。
     *
     * @param pjjglist 构造好的评教结果列表（包含题目答案）。
     * @return 提交成功返回 true，否则返回 false。
     */
    suspend fun submitEvaluation(pjjglist: List<JsonObject>): SpocResult<JsonElement>? {
        return try {
            val payload = buildJsonObject {
                putJsonArray("pjidlist") {}
                putJsonArray("pjjglist") { pjjglist.forEach { add(it) } }
                put("pjzt", "1")
            }
            val httpResponse =
                    getClient().post("$baseUrl/evaluationMethodSix/submitSaveEvaluation") {
                        contentType(ContentType.Application.Json)
                        setBody(payload)
                    }

            // 先读取原始字符串，便于诊断后端返回的真实字段
            val rawBody = httpResponse.bodyAsText()
            // 后端 result 可能是对象或数组，使用 JsonElement 适配
            val resp: SpocResult<JsonElement> = json.decodeFromString(rawBody)

            if (!resp.isSuccess()) {
                log.warn(
                        "Submit evaluation failed: code={}, message={}, result={}, content={}, raw={}",
                        resp.codeString(),
                        resp.message ?: resp.msg,
                        resp.result,
                        resp.content,
                        rawBody
                )
                log.warn("Submit payload: {}", payload)
            }
            resp
        } catch (e: Exception) {
            log.error("Failed to submit evaluation", e)
            null
        }
    }
}

private fun JsonElement?.asCodeString(): String? {
    return when (this) {
        null -> null
        is JsonPrimitive -> if (isString) content else intOrNull?.toString()
        else -> null
    }
}

fun <T> SpocResult<T>.codeString(): String? = code.asCodeString()

fun <T> SpocResult<T>.isSuccess(): Boolean {
    val c = code.asCodeString()?.lowercase()
    return c == "200" || c == "0" || c == "success"
}
