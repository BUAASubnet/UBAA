# 图书馆云打印

本页记录原生云打印接入依赖的协议与验收边界。

## 2026-11-12：Issue #123

按 [冻结参考](../references.md) 的两个固定提交核对。旧版的 `LibBookApi.kt`、`LocalLibBookApi.kt`、`LocalLibBookApiBackendTest.kt` 只处理座位；`buaa-api` 的 `src/api/cloud/` 处理北航云盘，`src/api/sso/`、`src/request.rs` 和 `src/store/cookies.rs` 没有云打印适配。对下表**每一项**，两个冻结来源的九列均不适用：不能借用座位或云盘的 URL、认证材料、DTO、重试或错误语义。协议依据为北航图书馆的官方网页、同源静态脚本与脱敏的直接观察。

| 操作 | 引导 URL 与 service | 跳转与最终 URL | 会话 | 方法与参数 | 头和编码 | 加密与签名 | DTO 与解析 | 缓存、并发、重试 | 错误与产品语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 登录检查与引导 | `/client/new/cprintPc/cprint.html`；`/api/client/Auth/SSoPage` 动态返回引导 | `/authcenter/toLoginPage` → `sso.buaa.edu.cn/login?service=…`，动态 `service` 指向打印站 `/authcenter/doAuth/<opaque>`；CAS 回调后经同站 `/api/client/Auth/SSOLogin` → `/api/client/Auth/UniEntry` → 上传页 | 打印站主机 Cookie `SESSIONID`、`OSESSIONID`；与学校 SSO 使用不同的临时 Cookie 容器，`Auth/Check` 响应的页面 SessionId 不进入应用合同 | `GET` 页面；`POST /api/client/Auth/Check` 空正文；`GET /api/client/Auth/SSoPage` 含 `backurl`；同站回调 GET，`UniEntry` 含 `SessionId`、`Func` | HTTPS（已观察到的同站应用回调升级为 HTTPS），JSON 回包；`Auth/Check` 需要 `Content-Length: 0` | 无客户端签名；复用 Core 学校会话 | `code`，引导 `result` 为 URL；站点账号字段不出 Core | 仅内存作用域，有限跳转；认证未通过则拒绝业务 | 缺少空正文长度时上游返回 HTTP 411；未登录时返回 `code=4`。SSO 表单需要用户恢复学校会话，不能自动提交账号密码 |
| 上传 | 同登录检查 | 官网脚本按跳转到 `/client/new/cprintPc/printDoc.html` 的 `code` 确定结果 | 同一打印站会话 | `POST /api/client/CloudPrint/Upload`；`szPath`、`dwColor`、`dwPaperId`、`dwDuplex`、`dwFrom`、`dwTo`、`dwCopies`、`BackURL`（队列页，`t` 毫秒时间戳） | `multipart/form-data`；同源 `Origin`、`Referer` | 无 | 只有合法队列跳转、唯一 `code=0` 才确认接收；不透传 `message` | 每文件独立一次发送，最多四路并行；未知结果不重发 | 入队后到现场设备取件；PDF、JPG、PNG、DOCX、XLSX、PPTX 各一份确认入队；TXT 本次被拒绝，不能推断为所有 TXT 均不支持 |
| 待打印列表、预览 | 同登录检查 | 同源 API，无业务跳转 | 同一打印站会话 | `GET /api/client/PrintJob/Get`（`timestamp`）；`GET /api/client/PrintJob/PreviewPage`（`timestamp`、`dwJobId`、`dwCreateTime`、`pageNo`） | JSON | 无 | `code`、`result`；列表 `dwJobId`、`szJobName`、`dwCreateDate`、`dwCreateTime`、`dwCopies`、`szPaperDetail`（内嵌 JSON）；预览 `result` 为 PNG Base64 | 不缓存文件内容；从同账号列表派生预览目标 | 单页合成 PDF 已验证能预览，预览不生成新任务 |
| 删除待打印任务 | 同登录检查 | 同源 API | 同一打印站会话 | `POST /api/client/PrintJob/Del`，字符串 `dwJobId`、`dwOldJobId` 为同一个列表 ID | JSON | 无 | `code=0` 成功 | 确认后单次发送，未知后查列表 | 真实删除未执行 |
| 扫描列表与下载 | 同登录检查 | 同源 API；官网批量操作逐个打开链接，未生成压缩包 | 同一打印站会话 | `GET /api/client/Scan/Get`（`timestamp`）；`GET /api/client/Scan/Download`（`dwJobId`，当前 HTML 的实际链接） | 列表 JSON，下载文件正文 | 无 | `szDisplayName`、`dwJobId`、`dwFileSize`、`dwSubmitDate`、`dwSubmitTime`；`dwStatus & 256` 标记过期 | 不缓存；下载使用列表派生目标 | 线上不触发扫描。官网没有独立预览请求；本机可用下载内容做预览。客户端将每组写为一份 PDF，逐份保存在用户选择的文件夹 |
| 删除扫描件 | 同登录检查 | 同源 API | 同一打印站会话 | `POST /api/client/Scan/Del`，字符串 `dwJobId` | JSON | 无 | `code=0` 成功 | 确认后单次发送，未知后查列表 | 过期项官网不开放删除，真实删除未执行 |
| 打印点 | 同登录检查 | 同源 API | 同一打印站会话 | `GET /api/client/Station/GetSrvList` 与 `GET /api/client/Station/GetList`（后者有 `timestamp`）；站点选择由前端分组，不发送站点序号 | JSON | 无 | 分组 `dwSN`、`szName`；设备 `dwDevSN`、`szName`、`dwStatus`、纸盒 `dwTrayPaper1–4`、能力位 `dwProperty`；设备分组 `floor(dwDevSN/1000)` | 仅按需读取 | 状态掩码按上线脚本的十进制值；设备状态是当前观察，不能用于远程放行打印 |
| 使用记录 | 同登录检查 | 同源 API | 同一打印站会话 | `POST /api/client/Report/DetailPageEx`（`timestamp`），`dwBeginDate`、`dwEndDate`（`YYYYMMDD` 字符串）、`dwType`（打印 1、复印 2、扫描 4）、`dwPageNo`、`dwRowCount=5` | JSON | 无 | `result`、`dwTotalPage`、`dwDate`、`dwTime`、`dwPages`、`dwPaperID` 与费用分值 | 按页、按日期查询，不缓存 | 空结果与失败区分；查询不产生消费 |

帮助页是静态操作说明。真实写入只有侧边浏览器中使用合成文件的直连上传试验，未进行线下打印。

## 2026-11-13：共用 WebVPN 路线

再次对照两个冻结来源：对上表的登录检查、待打印列表、预览、扫描列表、下载、上传、删除、打印点和使用记录，各项仍无同协议实现；九列继续以官网证据为准。已登录的侧边浏览器通过标准 WebVPN 编码地址打开上传页和扫描列表，并显示扫描条目。官网公共脚本用当前页面地址作为 SSO 的 `backurl`，上传脚本以当前页面地址生成 `BackURL`；两者随浏览器路线变化。打印服务的业务字段、PDF 校验、并发上限及写入不重试语义继续沿用上表。

原生实现使用同一全局路线策略和该路线已有的登录会话，派生的打印 Cookie 不写入共享会话。合成请求覆盖路线和协议边界。尚未验证原生 WebVPN 下完整 CAS 跳转、预览、实际下载或写入；浏览器点击下载未观察到下载完成，不能计作成功。

同一试用会话中，官网 `PreviewPage` 对合成 JPG、PNG 的第 1 页返回 `code=1`（文件格式转换错误），对合成 PDF 返回 PNG。客户端对新选择的 JPG、JPEG、PNG 在发送前生成单页 PDF，沿用已验证的 PDF multipart 合同；旧图片任务不假定存在可下载的原件。扫描列表观察到 `前缀+时间_序号_设备编号.pdf`，前缀包括中文「扫描件」和英文字母，末段与 `dwDevSN` 一致。同一秒内按序号升序排列。一次真实只读下载返回 `application/octet-stream`，内容具有 PDF 文件头且字节数与列表一致。合并只改变客户端保存行为：同设备相邻项间隔不超过一分钟且序号递增时归组，一次查询当前账号的列表，再在独立 Cookie 容器中并发最多四个同合同的 `Scan/Download`；按组内页序拼接 PDF，任何一份失败都不保存该组。

直连复核还发现部分 `application/octet-stream` 扫描下载响应在列表所报大小之后多出 1 至 13 字节，按列表大小截取的原件以独立的 `%%EOF` 行结束。客户端仅在该 MIME、PDF 文件头和列表边界处的结束标记均成立、且多出的数据不超过 16 字节时裁去后缀；少于列表大小的响应仍拒绝。Windows 预览复用同一原件下载接口，由系统 PDF 渲染器在本机逐页绘制。

合成用例可覆盖 CAS 回调及 Cookie 隔离、文件结果识别、四路上传与扫描保存行为。Windows 试用中复现了 HTTP 411 和缺失的 `UniEntry` 跳转；直连只读诊断确认该跳转设置打印站会话，并由生产 Core 成功读取扫描列表、打印点及使用记录。待打印列表的官网请求曾在约 30 秒后返回数据库超时（业务码 `16781313`），生产 Core 同样等待超时；上传入口与列表加载分离，真实上传仍待原生验收。原生 WebVPN 的完整引导、读取和写入仍需按各自授权范围复验。

## 错误路线投影

固定旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LibBookApi.kt`、`LocalLibBookApi.kt` 与对应测试仅实现座位服务，`LocalWebVpnSupport.kt` 提供通用 URL 包装。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/api/cloud/` 是北航云盘，`src/request.rs`、SSO 和 Cookie 模块没有云打印协议。对下列每项操作，两份冻结来源的九列均不适用；请求协议继续采用本页已记录的官网证据。

Core 使用既有 `Routed`、`RoutedError` 保留本次路线决策。Bridge 直接投影最终路线，Auto 回退后的失败属于 WebVPN，选路前的本地参数错误没有路线。原错误码、可重试性、批次顺序和写入结果语义保持不变，FRB 方法与 DTO 不变。

| 操作 | 引导与 service | 重定向与最终 URL | 会话作用域 | 方法与参数 | 头与编码 | 加密与签名 | DTO 与解析 | 缓存、并发、重试 | 错误与产品语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 待打印及扫描列表 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原 GET 与时间戳 | 不变 | 无新增 | 原文档字段 | 原单次跨路线回退 | 保留最终读取路线 |
| 单页预览 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原页码与列表目标 | 不变 | 无新增 | 原 PNG 字节 | 原单次跨路线回退 | 认证、转换和网络错误保留实际路线 |
| 单份扫描下载 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原列表目标 | 不变 | 无新增 | 原文件字节 | 原单次跨路线回退 | 下载失败保留实际路线 |
| 合并扫描下载 | 沿原协议 | 沿原校验 | 原独立 Cookie 容器 | 原列表目标集合 | 不变 | 无新增 | 原 PDF 合并 | 原四路并发与整组失败 | 选路前参数错误无路线，其余保留实际路线 |
| 打印点 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原两个 GET | 不变 | 无新增 | 原分组及设备字段 | 原单次跨路线回退 | 保留最终读取路线 |
| 使用记录 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原日期、类型与页码 | 不变 | 无新增 | 原记录及金额分值 | 原单次跨路线回退 | 保留最终读取路线 |
| 上传 | 沿原协议 | 原结果跳转判定 | 原独立 Cookie 容器 | 原 multipart 字段 | 不变 | 无新增 | 原逐项结果 | 最多四路，写入不重放 | 整批错误及逐项错误使用发送前确定的路线；选路前校验无路线 |
| 删除 | 沿原协议 | 沿原校验 | 原路线派生会话 | 原 JSON 目标 | 不变 | 无新增 | 原逐项结果 | 原顺序，结果未知后停止后续删除 | 整批错误及逐项错误使用发送前确定的路线；选路前校验无路线 |

验证使用合成 transport、临时文件与无会话原生调用，不执行学校认证、上传或删除。
