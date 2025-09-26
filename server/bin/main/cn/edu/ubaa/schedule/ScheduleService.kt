package cn.edu.ubaa.schedule

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class ScheduleService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {

    private val log = LoggerFactory.getLogger(ScheduleService::class.java)

    suspend fun fetchTerms(username: String): List<Term> {
        log.info("Fetching terms for username: {}", username)
        val session = sessionManager.requireSession(username)

        val response = session.getTerms()
        val body = response.bodyAsText()
        log.debug("Terms response status: {}", response.status)
        log.debug("Terms response body: {}", body)

        if (response.status != HttpStatusCode.OK) {
            throw ScheduleException("Failed to fetch terms. Status: ${response.status}")
        }

        val termResponse = runCatching {
            json.decodeFromString<TermResponse>(body)
        }.getOrElse { throwable ->
            log.error("Failed to parse terms response for username: {}", username, throwable)
            throw ScheduleException("Failed to parse terms response.")
        }

        if (termResponse.code != "0") {
            throw ScheduleException("Failed to retrieve terms. Code: ${termResponse.code}, Message: ${termResponse.msg}")
        }

        return termResponse.datas
    }

    suspend fun fetchWeeks(username: String, termCode: String): List<Week> {
        log.info("Fetching weeks for username: {} and termCode: {}", username, termCode)
        val session = sessionManager.requireSession(username)

        val response = session.getWeeks(termCode)
        val body = response.bodyAsText()
        log.debug("Weeks response status: {}", response.status)
        log.debug("Weeks response body: {}", body)

        if (response.status != HttpStatusCode.OK) {
            throw ScheduleException("Failed to fetch weeks. Status: ${response.status}")
        }

        val weekResponse = runCatching {
            json.decodeFromString<WeekResponse>(body)
        }.getOrElse { throwable ->
            log.error("Failed to parse weeks response for username: {}", username, throwable)
            throw ScheduleException("Failed to parse weeks response.")
        }

        if (weekResponse.code != "0") {
            throw ScheduleException("Failed to retrieve weeks. Code: ${weekResponse.code}, Message: ${weekResponse.msg}")
        }

        return weekResponse.datas
    }

    suspend fun fetchWeeklySchedule(username: String, termCode: String, week: Int): WeeklySchedule {
        log.info("Fetching weekly schedule for username: {}, termCode: {}, week: {}", username, termCode, week)
        val session = sessionManager.requireSession(username)

        val response = session.getWeeklySchedule(termCode, week)
        val body = response.bodyAsText()
        log.debug("Weekly schedule response status: {}", response.status)
        log.debug("Weekly schedule response body: {}", body)

        if (response.status != HttpStatusCode.OK) {
            throw ScheduleException("Failed to fetch weekly schedule. Status: ${response.status}")
        }

        val scheduleResponse = runCatching {
            json.decodeFromString<WeeklyScheduleResponse>(body)
        }.getOrElse { throwable ->
            log.error("Failed to parse weekly schedule response for username: {}", username, throwable)
            throw ScheduleException("Failed to parse weekly schedule response.")
        }

        if (scheduleResponse.code != "0") {
            throw ScheduleException("Failed to retrieve weekly schedule. Code: ${scheduleResponse.code}, Message: ${scheduleResponse.msg}")
        }

        return scheduleResponse.datas
    }

    suspend fun fetchTodaySchedule(username: String): List<TodayClass> {
        log.info("Fetching today's schedule for username: {}", username)
        val session = sessionManager.requireSession(username)

        val today = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
        val response = session.getTodaySchedule(today)
        val body = response.bodyAsText()
        log.debug("Today schedule response status: {}", response.status)
        log.debug("Today schedule response body: {}", body)

        if (response.status != HttpStatusCode.OK) {
            throw ScheduleException("Failed to fetch today's schedule. Status: ${response.status}")
        }

        val todayResponse = runCatching {
            json.decodeFromString<TodayScheduleResponse>(body)
        }.getOrElse { throwable ->
            log.error("Failed to parse today's schedule response for username: {}", username, throwable)
            throw ScheduleException("Failed to parse today's schedule response.")
        }

        if (todayResponse.code != "0") {
            throw ScheduleException("Failed to retrieve today's schedule. Code: ${todayResponse.code}, Message: ${todayResponse.msg}")
        }

        return todayResponse.datas
    }

    private suspend fun SessionManager.UserSession.getTerms(): HttpResponse {
        return try {
            val url = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do")
            client.get(url)
        } catch (e: Exception) {
            log.error("Error while calling terms endpoint for username: {}", username, e)
            throw ScheduleException("Failed to call terms endpoint.")
        }
    }

    private suspend fun SessionManager.UserSession.getWeeks(termCode: String): HttpResponse {
        return try {
            val url = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do?termCode=$termCode")
            client.get(url)
        } catch (e: Exception) {
            log.error("Error while calling weeks endpoint for username: {}", username, e)
            throw ScheduleException("Failed to call weeks endpoint.")
        }
    }

    private suspend fun SessionManager.UserSession.getWeeklySchedule(termCode: String, week: Int): HttpResponse {
        return try {
            val url = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do")
            client.post(url) {
                contentType(ContentType.Application.FormUrlEncoded)
                setBody("termCode=${termCode}&campusCode=&type=week&week=${week}")
            }
        } catch (e: Exception) {
            log.error("Error while calling weekly schedule endpoint for username: {}", username, e)
            throw ScheduleException("Failed to call weekly schedule endpoint.")
        }
    }

    private suspend fun SessionManager.UserSession.getTodaySchedule(date: String): HttpResponse {
        return try {
            val url = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do?rq=${date}&lxdm=student")
            client.get(url)
        } catch (e: Exception) {
            log.error("Error while calling today schedule endpoint for username: {}", username, e)
            throw ScheduleException("Failed to call today schedule endpoint.")
        }
    }
}

class ScheduleException(message: String) : Exception(message)

