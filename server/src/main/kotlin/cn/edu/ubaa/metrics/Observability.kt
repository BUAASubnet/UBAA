package cn.edu.ubaa.metrics

import cn.edu.ubaa.auth.CaptchaRequiredException
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.bykc.BykcException
import cn.edu.ubaa.cgyy.CgyyException
import cn.edu.ubaa.exam.ExamException
import cn.edu.ubaa.schedule.ScheduleException
import cn.edu.ubaa.spoc.SpocAuthenticationException
import cn.edu.ubaa.spoc.SpocException
import cn.edu.ubaa.user.UserInfoException
import cn.edu.ubaa.utils.UpstreamTimeoutException
import cn.edu.ubaa.ygdk.YgdkAuthenticationException
import cn.edu.ubaa.ygdk.YgdkException
import io.ktor.server.application.ApplicationCall
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Timer
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException

private const val BUSINESS_TIMER_NAME = "ubaa.business.operations"
private const val UPSTREAM_TIMER_NAME = "ubaa.upstream.requests"

class BusinessOperationScope internal constructor() {
  internal var result: String? = null

  fun markSuccess() {
    result = "success"
  }

  fun markBusinessFailure() {
    result = "business_failure"
  }

  fun markTimeout() {
    result = "timeout"
  }

  fun markUnauthenticated() {
    result = "unauthenticated"
  }

  fun markError() {
    result = "error"
  }
}

class UpstreamRequestScope internal constructor() {
  internal var result: String? = null

  fun markSuccess() {
    result = "success"
  }

  fun markTimeout() {
    result = "timeout"
  }

  fun markUnauthenticated() {
    result = "unauthenticated"
  }

  fun markError() {
    result = "error"
  }
}

object AppObservability {
  @Volatile private var registry: MeterRegistry? = null

  fun initialize(registry: MeterRegistry) {
    this.registry = registry
  }

  fun reset(registry: MeterRegistry? = null) {
    if (registry == null || this.registry === registry) {
      this.registry = null
    }
  }

  suspend fun <T> observeBusinessOperation(
      feature: String,
      operation: String,
      block: suspend BusinessOperationScope.() -> T,
  ): T {
    val startNanos = System.nanoTime()
    val scope = BusinessOperationScope()
    return try {
      val value = scope.block()
      recordTimer(
          BUSINESS_TIMER_NAME,
          mapOf(
              "feature" to feature,
              "operation" to operation,
              "result" to (scope.result ?: "success"),
          ),
          System.nanoTime() - startNanos,
      )
      value
    } catch (e: Throwable) {
      if (e is CancellationException) throw e
      recordTimer(
          BUSINESS_TIMER_NAME,
          mapOf(
              "feature" to feature,
              "operation" to operation,
              "result" to (scope.result ?: classifyBusinessThrowable(e)),
          ),
          System.nanoTime() - startNanos,
      )
      throw e
    }
  }

  suspend fun <T> observeUpstreamRequest(
      upstream: String,
      operation: String,
      block: suspend UpstreamRequestScope.() -> T,
  ): T {
    val startNanos = System.nanoTime()
    val scope = UpstreamRequestScope()
    return try {
      val value = scope.block()
      recordTimer(
          UPSTREAM_TIMER_NAME,
          mapOf(
              "upstream" to upstream,
              "operation" to operation,
              "result" to (scope.result ?: "success"),
          ),
          System.nanoTime() - startNanos,
      )
      value
    } catch (e: Throwable) {
      if (e is CancellationException) throw e
      recordTimer(
          UPSTREAM_TIMER_NAME,
          mapOf(
              "upstream" to upstream,
              "operation" to operation,
              "result" to (scope.result ?: classifyUpstreamThrowable(e)),
          ),
          System.nanoTime() - startNanos,
      )
      throw e
    }
  }

  fun recordRetryEvent(feature: String, operation: String, reason: String, amount: Double = 1.0) {
    incrementCounter(
        "ubaa.retry.events",
        mapOf("feature" to feature, "operation" to operation, "reason" to reason),
        amount,
    )
  }

  fun recordFallbackEvent(
      feature: String,
      operation: String,
      reason: String,
      amount: Double = 1.0,
  ) {
    incrementCounter(
        "ubaa.fallback.events",
        mapOf("feature" to feature, "operation" to operation, "reason" to reason),
        amount,
    )
  }

  fun recordSessionResolve(result: String, amount: Double = 1.0) {
    incrementCounter("ubaa.auth.session.resolve", mapOf("result" to result), amount)
  }

  fun recordCleanupRemovals(kind: String, count: Int) {
    if (count <= 0) return
    incrementCounter("ubaa.cleanup.removals", mapOf("kind" to kind), count.toDouble())
  }

  private fun recordTimer(name: String, tags: Map<String, String>, durationNanos: Long) {
    val activeRegistry = registry ?: return
    Timer.builder(name)
        .tags(*tags.flatMap { listOf(it.key, it.value) }.toTypedArray())
        .register(activeRegistry)
        .record(durationNanos, TimeUnit.NANOSECONDS)
  }

  private fun incrementCounter(name: String, tags: Map<String, String>, amount: Double) {
    if (amount <= 0.0) return
    val activeRegistry = registry ?: return
    activeRegistry
        .counter(name, *tags.flatMap { listOf(it.key, it.value) }.toTypedArray())
        .increment(amount)
  }
}

suspend fun <T> ApplicationCall.observeBusinessOperation(
    feature: String,
    operation: String,
    block: suspend BusinessOperationScope.() -> T,
): T = AppObservability.observeBusinessOperation(feature, operation, block)

internal fun classifyBusinessThrowable(error: Throwable): String {
  return when (error) {
    is UpstreamTimeoutException -> "timeout"
    is LoginException,
    is YgdkAuthenticationException -> "unauthenticated"
    is CgyyException ->
        if (error.code == "unauthenticated") "unauthenticated" else "business_failure"
    is CaptchaRequiredException,
    is UnsupportedAcademicPortalException,
    is BykcException,
    is SpocException,
    is YgdkException,
    is ScheduleException,
    is ExamException,
    is UserInfoException,
    is IllegalArgumentException,
    is io.ktor.server.plugins.ContentTransformationException -> "business_failure"
    else -> "error"
  }
}

internal fun classifyUpstreamThrowable(error: Throwable): String {
  return when (error) {
    is UpstreamTimeoutException -> "timeout"
    is LoginException,
    is SpocAuthenticationException,
    is YgdkAuthenticationException -> "unauthenticated"
    is CgyyException -> if (error.code == "unauthenticated") "unauthenticated" else "error"
    else -> "error"
  }
}
