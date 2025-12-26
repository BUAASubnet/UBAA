package cn.edu.ubaa.repository

import cn.edu.ubaa.api.ScheduleApi
import cn.edu.ubaa.model.dto.Term
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 学期信息仓库。
 * 负责学期数据的获取与内存缓存，确保学期列表在应用运行期间的一致性。
 */
class TermRepository(private val scheduleApi: ScheduleApi = ScheduleApi()) {
    
    private var cachedTerms: List<Term>? = null
    private val mutex = Mutex()

    /**
     * 获取学期列表。
     *
     * @param forceRefresh 是否忽略缓存强制从网络刷新。
     * @return 包含学期列表的 [Result]。
     */
    suspend fun getTerms(forceRefresh: Boolean = false): Result<List<Term>> {
        if (!forceRefresh) {
            val currentCache = cachedTerms
            if (currentCache != null) {
                return Result.success(currentCache)
            }
        }

        return mutex.withLock {
            // 双重检查锁定，防止并发重复请求
            if (!forceRefresh && cachedTerms != null) {
                return Result.success(cachedTerms!!)
            }

            scheduleApi.getTerms().onSuccess { terms ->
                cachedTerms = terms
            }
        }
    }
}