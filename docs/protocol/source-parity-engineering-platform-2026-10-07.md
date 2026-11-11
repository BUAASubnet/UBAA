# 工程修复：本地普通偏好与平台验证来源对照

日期：2026-10-07。生产修改前记录。基线 `06e4dfdb`；`just refs` 已验证旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版来源：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/BykcCourseFilterStore.kt` 的 StoredBykcCourseFilters/save/get/clear、`YgdkReminderStore.kt` 的 clear/clearWeekDone/clearTermDone；对应 commonTest 的 BykcCourseFilterStoreTest 和 YgdkReminderStoreTest。两个 clear 均只按账号键删除，不以旧内容解码成功为前提。当前 Dart 更严格的普通读取/保存拒绝坏数据规则继续保留。

示例来源：`src/store/mod.rs` 只有 cookies/cred，`src/api/boya/{mod,data,opt,core}.rs` 为学校业务接口，无同构本地 UI 筛选/提醒偏好。不能借其学校 URL、字段或凭据规则推断本地恢复。

| 操作 | CAS/service | 跳转/最终URL | Cookie/会话 | 方法/精确参数 | 头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 明确清除博雅普通偏好 | 本地，不适用 | 本地，不适用 | 不访问会话；现有scope/账号键不变 | 旧Settings.remove；现Plugin remove精确键，不做整表清空 | 无HTTP；删除无需JSON解码 | 无密码学协议；现有账号键哈希不变 | 保留三集合严格读写解析；clear不需要旧DTO | 保留全实例串行尾链和账号隔离，删除后允许重新保存 | 坏旧值不阻止明确删除；插件删除失败仍固定storageFailure；普通读写invalidData不变 |
| 明确清除提醒普通偏好 | 本地，不适用 | 本地，不适用 | 不访问会话/凭据 | 旧清三个账号键；现单一JSON键remove，不改键结构 | 无HTTP；删除无需解析旧内容 | 无；不涉及系统安全材料 | enabled/weekDoneKey/termDoneKey读写不变 | 保留scope/账号隔离、串行顺序和默认开启语义 | 删除失败仍传播；不隐式覆盖坏内容 |
| 原生插件通道验证 | 无CAS/学校服务 | 无学校跳转 | 不访问账号会话 | 读取系统连接类型、订阅系统变化；使用合成scope读写删除普通偏好 | 标准插件通道 | 不写凭据/密钥 | 标准结果列表/去重，不能当校园可达证据 | 显式取消订阅/清理合成键 | 缺注册/通道失败必须令测试失败；设备切网另行验收 |

本次 I05 恢复为用户明确删除损坏普通偏好的最小修复，有冻结旧版清除语义支持；不是扩大登录清理权限，不改学校读取、认证、写入、公开DTO或持久格式。正式用例先观察失败，后实现remove并验证账号隔离/插件错误/Host清除链。
