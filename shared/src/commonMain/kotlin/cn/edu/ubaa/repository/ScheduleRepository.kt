package cn.edu.ubaa.repository

import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.Settings
import kotlin.time.Clock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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

/** 默认在线查询，失败时回退到已手动本地化的课表；仅 update 写入持久存储。 */
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

  suspend fun loadTerms(offlineOnly: Boolean = false): Result<List<Term>> =
      onlineOrSaved(offlineOnly, { api.getTerms() }, ::terms)

  suspend fun loadWeeks(code: String, offlineOnly: Boolean = false): Result<List<Week>> =
      onlineOrSaved(
          offlineOnly,
          { api.getWeeks(code).mapCatching(::normalizeWeeks) },
          { weeks(code) },
      )

  suspend fun loadWeekly(
      code: String,
      week: Int,
      offlineOnly: Boolean = false,
  ): Result<WeeklySchedule> =
      onlineOrSaved(offlineOnly, { api.getWeeklySchedule(code, week) }, { weekly(code, week) })

  suspend fun loadTodayClasses(offlineOnly: Boolean = false): Result<List<TodayClass>> =
      onlineOrSaved(offlineOnly, { api.getTodaySchedule() }, ::todayClasses)

  private suspend fun <T> onlineOrSaved(
      offlineOnly: Boolean,
      online: suspend () -> Result<T>,
      local: () -> Result<T>,
  ): Result<T> {
    if (offlineOnly) return local()
    val owner = account()
    val result =
        try {
          online()
        } catch (e: CancellationException) {
          throw e
        } catch (e: Exception) {
          Result.failure(e)
        }
    currentCoroutineContext().ensureActive()
    (result.exceptionOrNull() as? CancellationException)?.let { throw it }
    if (account() != owner) return Result.failure(IllegalStateException("账号已切换，请重新加载课表"))
    // 无本地数据时保留真正的网络错误，不用“尚未导入”掩盖它。
    return if (result.isSuccess) result else local().takeIf { it.isSuccess } ?: result
  }

  private fun saved(): List<SemesterSchedule> = read(account() ?: error("请先登录并导入课表"))

  private fun normalizeWeeks(weeks: List<Week>): List<Week> =
      weeks.map {
        it.copy(startDate = normalizeDate(it.startDate), endDate = normalizeDate(it.endDate))
      }

  private fun normalizeDate(raw: String): String {
    // 本科接口返回 yyyy-MM-dd HH:mm:ss；缓存统一存日期，保证校验及离线范围比较正确。
    val date = raw.trim().substringBefore(' ').substringBefore('T')
    val match = Regex("""(\d{4})-(\d{1,2})-(\d{1,2})""").matchEntire(date)
    requireNotNull(match) { "课表日期格式无效，未覆盖本地数据" }
    val (year, month, day) = match.destructured
    return LocalDate(year.toInt(), month.toInt(), day.toInt()).toString()
  }

  private fun semester(code: String) =
      saved().firstOrNull { it.termCode == code } ?: error("此学期尚未导入，请点击课表本地化")

  fun terms(): Result<List<Term>> = runCatching {
    val snapshots = saved()
    check(snapshots.isNotEmpty()) { "尚未导入课表，请进入课表页点击课表本地化" }
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
    semester(code).schedules[week] ?: error("本地课表缺少此周，请点击课表本地化")
  }

  fun schedules(code: String): Result<Map<Int, WeeklySchedule>> = runCatching {
    semester(code).schedules
  }

  fun updatedAt(code: String?): String? =
      runCatching { saved().firstOrNull { it.termCode == code }?.updatedAt }.getOrNull()

  fun todayClasses(): Result<List<TodayClass>> = runCatching {
    val snapshots = saved()
    check(snapshots.isNotEmpty()) { "尚未导入课表，请进入课表页点击课表本地化" }
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
          val imported = api.importSemester(code).getOrThrow()
          val snapshot = imported.copy(weeks = normalizeWeeks(imported.weeks))
          currentCoroutineContext().ensureActive()
          check(account() == owner) { "账号已切换，请重新本地化课表" }
          check(code == null || snapshot.termCode == code) { "返回的课表学期与所选学期不一致，未覆盖本地数据" }
          check(snapshot.terms.any { it.itemCode == snapshot.termCode }) { "课表缺少学期信息" }
          check(snapshot.weeks.map { it.serialNumber }.toSet() == snapshot.schedules.keys) {
            "课表周次不完整，未覆盖本地数据"
          }
          // 本科 WeeklySchedule.code 实际为学号；研究生适配才填学期代码，不能统一比较。
          // 学期归属由请求参数、snapshot.termCode 和下面的 Week.term 校验。
          check(snapshot.weeks.distinctBy { it.serialNumber }.size == snapshot.weeks.size) {
            "课表周次重复，未覆盖本地数据"
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
