# 空教室旧版节次表对照（O3-E3a）

2026-09-09，实施基点78602e30（旧源码审查与行为RED先于图书馆补验提交）。冻结ubaa_old 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、examples/buaa-api efb7976bf513f38364b88aeb83d704586cff9b2a。本文在生产修改前建立，不代表实现/验收完成。

已逐页完整读取旧ClassroomQueryScreen.kt、ClassroomViewModel.kt及全部ViewModelTest，以及shared的ClassroomApi/LocalClassroomApi/Classroom DTO/LocalClassroomApiBackendTest；交叉复读示例api/class/core.rs和api/app/core.rs、主source-parity.md空教室两操作与B1/B2展示记录。当前UI为classroom_content.dart/academic_content.dart/classroom_queries.dart、detail_list.dart；公开数据来自ClassroomPresentation，原roomId/floorId/floorName/availableSections/queryDate/campus均保留。

| 旧版依据 | 必要优化 | 当前实现与本批目标 |
|---|---|---|
| ClassroomQueryScreen按楼栋分组，粘性表头“教室/1–14”，44高教室行、楼栋圆角Surface标题，绿色代表原kxsds中的空闲节次 | 手机/平板/电脑相同14列表；大字/窄宽必要横向滚动，名称可点详情；未列节次不能伪称已占用，缺失/非法原字段在详情保留 | 当前是教室大卡和节次Chip，宽屏另有180宽楼层侧栏；拟恢复旧节次表，删除正文常驻侧栏，低频ID/原值进入本地详情 |
| 旧校区1学院路/2沙河/3杭州、日期、搜索和楼栋筛选 | 用户最新要求优先：全部查询保留到顶栏右上按需面板，关闭保持草稿；真实campus/date归属不被未应用草稿改变 | 当前共享按需面板和真实选项已存在，继续使用；不恢复旧常驻多排筛选 |
| ClassroomViewModel楼栋筛选可再次取消；sortBuildings以无歧义floorId排序，否则楼名自然排序，结果按原Map分组 | 不把同floorId不同楼名合并、不把同楼名不同floorId拆为错误楼栋；旧筛选词命中楼名却返回空教室列表的问题不继承 | 当前按floorId分组且只在桌面可本地二次筛选，拟按父楼名分组、查询面板统一筛选；保原完整数据及本地字段搜索 |
| 旧ClassroomTable完整LazyColumn无分页 | 没有服务端分页时全部已加载教室连续滚动；真正服务端pagination必须保留 | 当前通用20条本地分页切碎楼栋，拟仅对无服务端分页的typed教室取消本地截断；大量列表仍懒构建 |

## 逐操作协议与行为边界

| 操作 | CAS/启动与service | 跳转与最终URL | Cookie/session | 方法与参数 | Header/body编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 空教室会话同步 | 原LocalClassroomApi.classroomSyncUrl完整编码service及noAutoRedirect=1，主source-parity.md已有精确值；示例iClass与微信小程序CAS不等价 | 原共享跟随跳转，200–399标记同步；不改变Core允许主机/路由 | 每路线后端独立syncMutex/sessionSynced，重置后重新同步；不借示例共享token | GET精确原URL，无新参数 | 原LOCAL_CLASSROOM_USER_AGENT，无body | 无新增 | 不将同步返回体投影给宿主 | 原双重检查互斥，不新增学校请求 | 尽力同步，后续业务错误仍原分类，不冒充业务成功 |
| 日期/校区查询及楼栋/节次筛选 | 原https://app.buaa.edu.cn/buaafreeclass/wap/default/search1，不借示例Class API | 本次不跟随，401/SSO Location/HTML认证标记失效；当前Core规则不变 | 当前路线Cookie及本地认证预检，宿主不接触会话 | GET xqid、floorid空、date严格日期；既有App floor/section只本地过滤 | 原UA、JSON Accept、路线转换Referer /site/classRoomQuery/index、XHR，无body | 无新增 | 原e:int/m:string/d.list map；id/floorid/name/kxsds字符串；未知/缺失不造空闲。仅从公开ClassroomPresentation渲染1–14表，原字符串详情保留 | 仍原查询，无新增结果缓存/并发；取消UI本地20分页不增加请求，当前query/stale/迟到保护不变 | 原invalid_input/认证/网络/解析错误，不放宽成功条件或伪空；生产只读无学校写入 |

示例没有等价空教室查询协议、表格或DTO，不借其URL、Sessionid、加密或错误行为。Core facade、Bridge v9、CLI v10、认证与业务资格均不变。先增加表格位置/完整列表/本地详情的行为RED，再实现并三端实际渲染复验，更新84清单及证据后提交。


## 实施与实屏复核

已按上述表恢复原14节表格和圆角楼栋标题；以父楼名分组保原顺序，不按相同floorId错误合并。仅取消本地20截断，真实服务端分页不变。原字段可从本地详情读取，全部typed字段可检索，03仍按旧整数解析显示第3节，15等越界原值只保详情，不造第15列。缺省/非法空闲字段不标占用或虚造空闲。

首轮实屏发现大字横滚使楼栋标题裁切，后续又发现教室列滚出；分别观察边界413.2>374、名称left=-46.7的行为RED后，增加按可视宽度固定标题/来源及教室列，纵向表头仍粘性，必要横向滚动条可见。四项本批UI行为与既有回归通过；最终三端r3各14通过，64合成原图见old-e3a-native。生产Direct38秒/WebVPN54秒均158→144→27条只读通过，实际route一致、业务写入0。Direct在最后纯固定列调整前通过；读取/查询/本地详情未改变，最终列布局由三端r3证明。

CUA独立macOS已浏览完整列表、打开第42项详情和查询面板，随后AXError.failure；重连、reset会话和本次fake hot restart后仍受限，CoreGraphics只读状态screenLocked=false/onConsole=true，未改系统权限或绕过锁屏。此工具限制记录到P6，不把未操作的独立鼠标选择标为PASS。
