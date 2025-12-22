package cn.edu.ubaa.signin

import cn.edu.ubaa.model.dto.SigninActionResponse
import cn.edu.ubaa.model.dto.SigninStatusResponse
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap

object SigninService {
    private val clientCache = ConcurrentHashMap<String, SigninClient>()

    private fun getClient(studentId: String): SigninClient {
        return clientCache.getOrPut(studentId) { SigninClient(studentId) }
    }

    suspend fun getTodayClasses(studentId: String): SigninStatusResponse {
        val client = getClient(studentId)
        val today = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"))
        val classes = client.getClasses(today)
        return SigninStatusResponse(code = 200, message = "Success", data = classes)
    }

    suspend fun performSignin(studentId: String, courseId: String): SigninActionResponse {
        val client = getClient(studentId)
        val (success, message) = client.signIn(courseId)
        return SigninActionResponse(
                code = if (success) 200 else 400,
                success = success,
                message = message
        )
    }
}
