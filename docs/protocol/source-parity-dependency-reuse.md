# 通用依赖收敛：实施前来源裁决

2026-10-07，基线 2eae5549。用户要求按审计建议实施收敛，开发阶段不承担旧数据迁移；本文件在生产修改前建立。冻结 old 为 1f4b8f8412272b6a423d4ad92b396e3db721e6f3，buaa-api 为 a63712fa2ae0a6c8066197063ddee98e3a6b5b81。完整请求层对照沿 [source-parity.md](source-parity.md)，以下按本次替换操作补九列。

来源：old 的 LocalConnectionAuth.kt、LocalWebVpnSupport.kt、LocalSpocSupport.kt、LocalLibBookCrypto.kt、LocalCgyyCaptchaSupport.kt 及 jvmMain/androidMain 的 PlatformAes 实现和既有 fixture 测试；示例的 store/cookies.rs、crypto/aes.rs、api/spoc/core.rs。old 接口/DTO 沿原逐业务对照；示例没有 Cgyy/LibBook 等价业务，不借用其他业务参数。

| 操作 | CAS/入口与 service | 跳转/最终 URL | Cookie/会话 | 方法/参数 | 头/正文 | 加密/签名 | DTO/字段 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| Cookie 接收/发送 | 两来源挂在各 HTTP 客户端，本次无新增入口 | 保持手动逐跳，以请求 URL 匹配 | old 自写过期，示例忽略过期；用户已批准标准优先级修复，保留双路线隔离 | Set-Cookie 多值逐项，Cookie 头发送 | 保留 name=value 组合 | 无 | 保留 StoredCookie 格式与注入时钟，库仅内部使用 | 保留快照/CAS/代次，不启用全局 Jar | 格式错误安全错误；无效域忽略；Max-Age 优先，非正值删除；不记录材料 |
| WebVPN 主机编解码 | old 固定 d.buaa.edu.cn，示例无同等业务入口 | scheme[-port]/主机段/path/query/fragment 不变 | 仍按网关 URL 匹配 | 无独立请求 | 十六进制与截断长度不变 | old AES/CFB/NoPadding，key/IV wrdvpnisthebest!；改用 cfb-mode/hex | UTF-8 主机和既有返回值 | 无新缓存 | 畸形输入安全错误，避免切片 panic |
| SPOC 参数加密 | 两来源 spocnewht/cas，service 沿原对照 | 原 auth/final 校验 | 原 Inco token/路线代次 | 原 JSON param 包装 | Base64 不变 | 两来源 key inco12345678ocni、IV ocni12345678inco；CBC 零填充，整块不加块；cbc/ZeroPadding | 原参数/响应 DTO | 无新缓存/重试 | 原业务错误 |
| LibBook 预约编码 | old 原入口，示例无等价协议 | 原 final 校验 | 原路线凭据 | seat_id/segment/day/start_time/end_time，后两项空 | JSON 顺序/Base64 不变 | old 日期数字+逆序 key、IV ZZWBKJ_ZHIHUAWEI、CBC/PKCS7；cbc | 原 EncryptedReserveBody | 不发真实提交 | 原 invalidInput/internal |
| Cgyy 验证码编码 | old 原入口，示例无等价协议 | 原 final 校验 | 原 challenge/token 代次 | x/y=5 与 token---pointJson | 原 JSON/Base64 | old ECB/PKCS5Padding，AES 等价 PKCS7，16/24/32 字节 key；ecb/cipher | 原 DTO | 原一次性 challenge | 无效 key 安全错误，不记录验证码 |
| 平台照片/目录/偏好/网络/关于 | 本地，无 CAS/service | 外链沿 old AppLink，学校跳转不变 | 本地账号/注销代次保留 | 插件 API，不增学校请求 | 照片字节/元信息与 10 MiB 上限 | 普通偏好不放密码，成绩仍 Core 加密 | 现有平台接口，宿主能力组合扩展 | 插件生命周期/去重/持久化集中平台层 | 取消/拒绝/不可用稳定错误，原始路径与异常不进 UI |

Cookie 冲突裁决：上轮实际代码合成 RED 证实 Expires 错误覆盖 Max-Age，无真实上游触发证据。用户“按你的建议”明确接受该已披露标准修复，按 RFC 6265 实施，不复制冻结简化/缺陷。保留来源支持的请求/持久化边界，不额外加入公共后缀策略。

照片：old composeApp/androidMain 的 PlatformImagePicker 使用 TakePicturePreview。插件替换仍保留照片/表单代次/内存上限，不增加 UI 操作；临时文件与拍照尺寸差异另在平台阶段明确记录。
