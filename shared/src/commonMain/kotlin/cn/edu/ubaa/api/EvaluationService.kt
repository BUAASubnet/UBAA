package cn.edu.ubaa.api

import cn.edu.ubaa.model.evaluation.EvaluationCourse
import cn.edu.ubaa.model.evaluation.EvaluationCoursesResponse
import cn.edu.ubaa.model.evaluation.EvaluationProgress
import cn.edu.ubaa.model.evaluation.EvaluationResult
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

class EvaluationService(private val apiClient: ApiClient) {

    /** 获取所有评教课程（包括已评教和未评教），附带进度信息。 */
    suspend fun getAllEvaluations(): EvaluationCoursesResponse {
        return try {
            apiClient.getClient().get("/api/v1/evaluation/list").body()
        } catch (e: Exception) {
            println("Error fetching evaluations: ${e.message}")
            EvaluationCoursesResponse(courses = emptyList(), progress = EvaluationProgress(0, 0, 0))
        }
    }

    /**
     * 获取待评教课程列表（仅未评教课程）。
     * @deprecated 使用 getAllEvaluations() 获取完整信息。
     */
    suspend fun getPendingEvaluations(): List<EvaluationCourse> {
        return getAllEvaluations().courses.filter { !it.isEvaluated }
    }

    suspend fun submitEvaluations(courses: List<EvaluationCourse>): List<EvaluationResult> {
        return try {
            apiClient
                    .getClient()
                    .post("/api/v1/evaluation/submit") {
                        contentType(ContentType.Application.Json)
                        setBody(courses)
                    }
                    .body()
        } catch (e: Exception) {
            println("Error submitting evaluations: ${e.message}")
            // Return failed results for all input courses on network error
            courses.map { EvaluationResult(false, "Network/Server Error: ${e.message}", it.kcmc) }
        }
    }
}
