package cn.edu.ubaa.repository

import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.Settings
import kotlin.time.Clock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** 一次完整导入的学期；所有周次成功后才替换本地版本。 */
@Serializable
data class SemesterSchedule(
    val terms: List<Term>,
    val termCode: String,
    val weeks: List<Week>,
    val schedules: Map<Int, WeeklySchedule>,
    val updatedAt: String = "",
)

object ScheduleStore {
  private val revision = MutableStateFlow(0L)
  val changes = revision.asStateFlow()
  private var backing: Settings? = null
  var settings: Settings
    get() = backing ?: Settings().also { backing = it }
    set(value) {
      backing = value
    }

  private val json = Json { ignoreUnknownKeys = true }
  private const val ACCOUNT = "schedule_account"

  fun account(): String? = settings.getStringOrNull(ACCOUNT)

  fun useAccount(account: String) {
    require(account.isNotBlank())
    settings.putString(ACCOUNT, account)
    revision.update { it + 1 }
  }

  fun forgetAccount() {
    settings.remove(ACCOUNT)
    revision.update { it + 1 }
  }

  fun read(account: String): List<SemesterSchedule> =
      ScheduleSnapshotStorage(settings).read(account)?.let {
        json.decodeFromString<List<SemesterSchedule>>(it)
      } ?: emptyList()

  fun write(account: String, semesters: List<SemesterSchedule>) {
    ScheduleSnapshotStorage(settings).write(account, json.encodeToString(semesters))
    revision.update { it + 1 }
  }

  fun hasSavedSchedule(): Boolean =
      runCatching { account()?.let { read(it).isNotEmpty() } == true }.getOrDefault(false)
}

/** 浏览只读本地；唯一联网入口为用户触发的 update。 */
class ScheduleRepository(
    private val api: ScheduleApi = ScheduleApi(),
    private val account: () -> String? = ScheduleStore::account,
    private val read: (String) -> List<SemesterSchedule> = ScheduleStore::read,
    private val write: (String, List<SemesterSchedule>) -> Unit = ScheduleStore::write,
    private val today: () -> LocalDate = {
      Clock.System.now().toLocalDateTime(TimeZone.of("Asia/Shanghai")).date
    },
) {
  private val updateMutex = Mutex()

  private fun saved(): List<SemesterSchedule> = read(account() ?: error("请先登录并导入课表"))

  private fun semester(code: String) =
      saved().firstOrNull { it.termCode == code } ?: error("此学期尚未导入，请点击更新课表")

  fun terms(): Result<List<Term>> = runCatching {
    val snapshots = saved()
    check(snapshots.isNotEmpty()) { "尚未导入课表，请进入课表页点击更新课表" }
    val current = snapshots.first().terms.firstOrNull { it.selected }?.itemCode
    snapshots
        .flatMap { it.terms }
        .distinctBy { it.itemCode }
        .map { it.copy(selected = it.itemCode == current) }
  }

  fun weeks(code: String): Result<List<Week>> = runCatching {
    val date = today().toString()
    semester(code).weeks.map { it.copy(curWeek = date >= it.startDate && date <= it.endDate) }
  }

  fun weekly(code: String, week: Int): Result<WeeklySchedule> = runCatching {
    semester(code).schedules[week] ?: error("本地课表缺少此周，请点击更新课表")
  }

  fun schedules(code: String): Result<Map<Int, WeeklySchedule>> = runCatching {
    semester(code).schedules
  }

  fun updatedAt(code: String?): String? =
      runCatching { saved().firstOrNull { it.termCode == code }?.updatedAt }.getOrNull()

  fun todayClasses(): Result<List<TodayClass>> = runCatching {
    val snapshots = saved()
    check(snapshots.isNotEmpty()) { "尚未导入课表，请进入课表页点击更新课表" }
    val date = today()
    // 位图的尾部空周可能跨到下一学期，优先使用开学日期更晚的已保存学期。
    val snapshot =
        snapshots
            .filter {
              it.weeks.any { week ->
                date.toString() >= week.startDate && date.toString() <= week.endDate
              }
            }
            .maxByOrNull { it.weeks.minOf { week -> week.startDate } }
    val week =
        snapshot?.weeks?.firstOrNull {
          date.toString() >= it.startDate && date.toString() <= it.endDate
        }
    snapshot
        ?.schedules
        ?.get(week?.serialNumber)
        ?.arrangedList
        ?.filter { it.dayOfWeek == date.dayOfWeek.ordinal + 1 }
        .orEmpty()
        .sortedBy { it.beginTime ?: "" }
        .map {
          TodayClass(
              it.courseName,
              it.placeName,
              listOfNotNull(it.beginTime, it.endTime).joinToString("-"),
              it.courseName,
          )
        }
  }

  suspend fun update(code: String? = null): Result<SemesterSchedule> =
      updateMutex.withLock {
        try {
          val owner = account() ?: error("请先登录后更新课表")
          val snapshot = api.importSemester(code).getOrThrow()
          check(account() == owner) { "账号已切换，请重新更新课表" }
          check(snapshot.terms.any { it.itemCode == snapshot.termCode }) { "课表缺少学期信息" }
          check(snapshot.weeks.map { it.serialNumber }.toSet() == snapshot.schedules.keys) {
            "课表周次不完整，未覆盖本地数据"
          }
          check(
              snapshot.weeks.distinctBy { it.serialNumber }.size == snapshot.weeks.size &&
                  snapshot.schedules.values.all { it.code == snapshot.termCode }
          ) {
            "课表学期或周次不一致，未覆盖本地数据"
          }
          snapshot.weeks.forEach {
            check(
                it.term == snapshot.termCode &&
                    it.serialNumber > 0 &&
                    LocalDate.parse(it.startDate) <= LocalDate.parse(it.endDate)
            ) {
              "课表日期无效，未覆盖本地数据"
            }
          }
          val updated =
              snapshot.copy(
                  updatedAt =
                      Clock.System.now()
                          .toLocalDateTime(TimeZone.of("Asia/Shanghai"))
                          .toString()
                          .take(16)
                          .replace('T', ' ')
              )
          write(owner, listOf(updated) + read(owner).filterNot { it.termCode == updated.termCode })
          Result.success(updated)
        } catch (e: CancellationException) {
          throw e
        } catch (e: Exception) {
          Result.failure(e)
        }
      }
}
