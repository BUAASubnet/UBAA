package cn.edu.ubaa

import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalTime::class)
fun testClock() {
  val now = Clock.System.now()
  val localDateTime = now.toLocalDateTime(TimeZone.currentSystemDefault())
  println(localDateTime)
}
