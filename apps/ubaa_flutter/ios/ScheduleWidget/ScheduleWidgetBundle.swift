import SwiftUI
import WidgetKit

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        // WidgetBundleBuilder 不支持按版本二选一；配置组件为 iOS 17+ 能力，
        // iOS 15/16 不再单独提供旧版组件。
        if #available(iOS 17.0, *) {
            TodayConfiguredWidget()
            UpcomingConfiguredWidget()
            WeekConfiguredWidget()
        }
        // 控制中心控件（iOS 18+）暂不注册：OpenURLIntent 在模拟器 ad-hoc 签名下
        // 触发 AppIntentsLiveEntityService 崩溃并连累组件添加页；恢复时从历史取回。
    }
}
