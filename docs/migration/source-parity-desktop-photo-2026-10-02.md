# Windows/Linux系统选图接线

日期：2026-10-02，起点`345d1236`。冻结旧版`1f4b8f84`的`composeApp/src/jvmMain/kotlin/cn/edu/ubaa/ui/common/util/PlatformImagePicker.jvm.kt`：打开系统FileDialog，用户取消不返回图片；选定后读取字节、basename和Files.probeContentType；桌面不支持拍照。共同表单`YgdkClockinFormScreen.kt`接选择、预览、重选和清除。示例`buaa-api@a63712fa`没有本地桌面UI/选图能力；学校上传协议不改，不类比其它接口。

| 操作 | 旧版行为与当前选择 | 网络/会话/参数/header/crypto/DTO | 生命周期与错误 |
|---|---|---|---|
| 选择 | 系统单文件对话框，取消返回空；Win/Linux接Flutter官方file_selector，其它平台保留现有原生选择 | 无学校请求、URL、Cookie、表单或crypto；路径只在Platform内部，Host仅YgdkPhotoInput | 单次在途；取消不覆盖旧图，平台异常统一固定错误 |
| 读取 | 保留原图字节、basename与MIME；当前既有10MiB限制继续应用，先检查长度并流式限额 | 不落盘复制、不上传；MIME按已选文件名/文件头识别，复用既有canonical字段校验 | 空文件、超限、非image或不安全basename拒绝，错误不含路径/正文 |
| 权限 | 桌面用户在对话框明确选择单个文件，不需要申请移动端相册库权限 | photos/files仅允许进入系统选择器，不产生广泛目录授权；其它权限仍由既有Gateway处理 | 不声称桌面相机/位置可用，未实现能力继续返回unavailable |
| 后续提交 | 旧表单选图/预览/重选/清除；当前唯一WriteCoordinator与Core fresh资格不改 | 学校上传URL、方法、参数、headers、编码、token、crypto全沿当前已证Ygdk合同 | 本次只做本地能力接线，真实学校提交为0，合成backend验证表单 |

官方资料：Flutter维护的[file_selector](https://pub.dev/packages/file_selector)说明Windows/Linux原生文件选择，`openFile`取消返回null；[MIME识别API](https://pub.dev/documentation/mime/latest/mime/lookupMimeType.html)说明优先检查文件头。锁定file_selector 1.1.0，MIME复用2.0.0接口，仍以当前pubspec.lock和实际解析为准。平台能力依赖进入真实原生注册清单；单元测试不冒充Windows/Linux实际窗口或构建验收。
