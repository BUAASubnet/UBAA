# O3-D4阳光打卡旧版依据与实施边界

2026-09-09，实施前对照及实施后回写。基点e812798e；冻结old=6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、examples=efb7976bf513f38364b88aeb83d704586cff9b2a。旧YgdkHomeScreen、ViewModel、ClockinFormScreen、API/DTO/Local与BackendTest已逐段读取；examples模块清单无阳光协议，不借其app或spoc字段类比。

| 旧版依据 | 必要优化 | 当前与实施对应 |
|---|---|---|
| HomeScreen:67–123，学期/本周次数→首页提醒→打卡记录，右下新增；ViewModel.refreshAll先概览再page1记录 | 顶栏唯一刷新与按需查询，不再正文重复刷新；保留摘要和记录同页，项目到新增流程再出现 | 已实现typed概要与记录卡、右下新增；项目仅在新增选择出现，周统计不丢失 |
| HomeScreen:169–224，项目/地点/开始结束、提交时间/图片张数/是否分享 | 保留卡片顺序，低频编号及未知原始state进本地详情；长名称换行可读 | Bridge只含imageCount，没有URL；历史图片仅计数，不伪造图库 |
| ViewModel:143–163，page+1追加记录、失败保留旧列表 | 保留加载更多，按需面板仍能指定原page/size；刷新、筛选、返回不丢草稿 | page/size一基，不能改为研讨室零基；去重只凭公开recordId并标明重复，不重算总数 |
| ClockinForm:165–315，项目→时间→地点→照片→分享→底部提交 | 保留顺序，复用现有typed目标和照片能力；时间日期明确，关闭面板保存草稿 | 旧透明图片/自动补时间不继承：现Core要求明确照片、时间及fresh资格；不为UI改写合同或自动造数据 |
| YgdkReminderStore与ViewModel首页提醒 | 与后续首页六来源共同接入账号隔离的提醒状态 | 不能做不生效开关；本批先记录此依赖，不声称已恢复 |

## 两操作九列

两读分别复用source-parity.md“阳光打卡只读查询”九列，且已复读LocalYgdkApi:63–105与BackendTest:63–179：OAuth入口app.buaa.edu.cn/uc/api/oauth/index，code换业务campusAppLogin；query/fragment code及既有最多10跳规则不变，完整允许主机集合仍为既有未决项，不臆造白名单。uid/token只存路线隔离业务会话内，认证失效代数/单飞/一次重登沿Core现合同。POST表单与query同时携既有参数、X-Requested-With头，无新加密签名。概览读取体育分类→项目→可选汇总/学期，records读分类→项目→getList(page/limit/classify_id/user_id)；所有上游URL/字段/编码不变。DTO全部来自Bridge白名单：term/week/month/day/good计数、可空目标、分类/默认项目/项目原顺序；记录ID、item、时间、place、imageCount、isOpen、state、createdAt/Label与服务端page/total/hasMore。code=1、-98及非法输入/错误分类不改，不将失败当空记录。

## 组合读取与业务保护计划

先补投影RED：零计数/未知目标、项目为空仍有概要；记录公开状态/图片数/原始state；普通与固定路线回读相同投影。保留原_ygdkSubmitActions的父分类、正ID、名称、唯一性、allowed与完整target校验，默认项目和进度不授写权限。

旧首页需要概览和记录同页。默认后台loadFeature仍只读取概览，避免首页刷新无端增加记录请求；显式进入阳光首页后再执行当前页读取，记录应固定到本次概览实际路线，使用已有ygdkRecordsOnRoute，不第二次Auto选路。记录失败保留本次概览并显示安全局部错误；不沿用其他路线记录，不伪称记录为空。固定路线写后回读方法仍仅执行原协调器指定读取，UI不得因回读触发额外Auto查询。组合接线必须先有请求顺序/同路线/部分失败/隐藏页不追加请求的RED；未完成前不标首页恢复。

实施后依次检查手机/平板/macOS实际卡片、按需面板、空/错/stale/loading/长文/多页与合成新增准备取消；P5再完成单次commit/固定回读/unknown等。真实.env.local只读单独两路线验证，真实写入禁止。

## 实施后对应

`feature/overview.dart`与`presentation/ygdk.dart`承载公开投影；`bridge/read/ygdk.dart`普通/pinned读取复用mapper。显式首页概览后固定本次actual route读记录，默认后台概览、写后指定回读不增加Auto。`features/ygdk/home_flow.dart`保留概要、追加相邻同路线记录，显示局部错误；宿主传入同requestRevision的固定回读记录，不额外查询。`record_card.dart`按旧顺序展示，编号/state进入本地详情且仍可搜索。服务端页码/total/hasMore不靠本地长度重算，未知目标不伪造资格。

宿主可见性、连续追加及写后固定回读3项测试通过；首次写后页面没有显示更新记录的行为RED后补接线，未更改WriteCoordinator。新增表单暂复用既有Dialog，仅准备和取消已原生通过；旧独立表单与完整草稿、一次commit/失败/unknown继续P5。提醒开关与首页六来源仍待接入，不把本批只读页面验收当全功能完成。
