# P5-E 原生照片能力来源核对（2026-09-10）

基点f9115633。CAP-01生产只读已暴露缺口：默认photo.capability无原生实现，宿主安全隐藏新增入口。此批补平台能力，不改变Core/Bridge、学校请求或写入资格；真实选择照片只在显式脱敏业务backend中操作，生产账号仅浏览表单，禁止上传/提交。

| 冻结依据 | 必要优化 | 当前实施位置 |
|---|---|---|
| common PlatformImagePicker：bytes/fileName/mimeType、取消无回调；Ygdk表单选择/清除/原文件信息 | 保持当前10MiB、只读原文件、取消保原图、退出释放、未知/失败明确；不恢复透明图片兜底 | packages/ubaa_platform/src/media.dart及共享独立表单 |
| Android GetContent image/*、displayName/getType；TakePicturePreview→JPEG92 | 系统授予所选内容的临时读取，不申请全量媒体库；读取大小限制；拍照作为原能力后续单独接线验收，未列为本批已完成功能 | Android PhotoChannel与MainActivity |
| JVM FileDialog LOAD、basename/MIME；相机不可用 | macOS NSOpenPanel仅用户选中文件只读；原路径不离开原生层，读取错误不当取消 | macOS PhotoChannel与窗口接线 |
| iOS明确“图片选择暂未接入”，无已实现旧相册能力 | 为本轮手机/平板一致任务补系统PHPicker，用户选择后才可读所选照片，无全量相册访问 | iOS PhotoChannel与Engine注册 |
| examples无图片选择UI或阳光等价协议 | 不借上游字段/加密/错误；沿现有阳光九列协议和typed写入 | docs/migration/source-parity.md既有阳光矩阵不变 |

边界：permission.request的photos表示能请求系统选择器，不代表获全相册权限；系统选择器内选择是取得单张内容的授权，取消返回null。其他权限/凭据/位置仍不可用，不因接线照片而报告它们可用。iOS PHPicker、Android系统GetContent与OHOS PhotoViewPicker均仅选定内容；macOS添加user-selected.read-only entitlement，不能开放整个目录或写权限。所有native异常使用固定code/message且无details，跨通道不传URI/路径/原始系统错误。

官方依据：Apple PHPickerViewController及Selecting Photos and Videos in iOS（https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios）；NSOpenPanel（https://developer.apple.com/documentation/appkit/nsopenpanel）；Android permission alternatives及Photo Picker（https://developer.android.com/privacy-and-security/minimize-permission-requests）。实际签名以锁定本机SDK头文件为准。

验收：先原生默认probe不可用RED及平台错误不应伪装取消RED；最小原生接线、方法通道聚焦、实际选择/取消/预览/重选/清除、明暗与两端/真实Mac观察，全部写入使用显式内存backend。Windows/Linux原生照片尚待接线与对应环境核验，不冒称六平台全部完成；OHOS仅构建不代替设备。


P5-E最终审查补强：原生展示名不得修剪或替换掉非法原始值以绕过Dart canonical约束。Apple/Android对已提供的首尾空白、路径、引号、控制字符及超128码点展示名明确拒绝；仅Android provider未提供名称时使用明确的“所选图片”默认展示名，OHOS不从不透明URI猜文件名。Swift合成文件拒绝分支、Android构建与三端原生接线重新验证；原始文件保持只读。此补强不改变业务字段或资格。


## P5-F Android旧版拍照恢复前核对（2026-09-12）

基点5d988362。再次逐行读取冻结PlatformImagePicker.kt、Android PlatformImagePicker.android.kt及YgdkClockinFormScreen.kt照片区：图片与“拍摄照片”同一行，仅canCapturePhoto=true显示后者；Android使用TakePicturePreview返回Bitmap，在内存压缩JPEG质量92，以camera_时间戳.jpg和image/jpeg回传。JVM/iOS/OHOS不由此类推新增相机能力。examples无此UI或阳光拍照实现；学校上传/提交九列继续沿source-parity-ui-campus，不改变CAS、Cookie、参数、DTO、资格、缓存/并发、实际路线或错误合同。

AndroidX官方源码[TakePicturePreview](https://android.googlesource.com/platform/frameworks/support/+/dd97834aa54671ee1f56d65fa46668b4ffeb57e8/activity/activity/src/main/java/androidx/activity/result/contract/ActivityResultContracts.kt)核实其Intent为MediaStore.ACTION_IMAGE_CAPTURE、成功结果Bitmap来自data extra。当前AndroidManifest没有CAMERA权限；恢复系统相机委托，不新增直接相机/存储权限或持久照片文件，能力探测需核对可处理Intent。必要优化为原生及Dart均受10MiB约束、固定错误、取消保原图、选择/拍照单pending及代次失效保护。拍照作为可选本地平台接口穿过宿主/共享UI，不能放宽学校业务写入资格。先记录缺少拍照能力行为RED，再实现、构建、脱敏原生渲染；真实设备相机操作仍独立验收。
