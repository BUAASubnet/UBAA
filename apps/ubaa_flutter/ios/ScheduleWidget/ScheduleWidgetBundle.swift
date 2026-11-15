import AppIntents
import SwiftUI
import WidgetKit

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayScheduleWidget()
        UpcomingScheduleWidget()
        WeekScheduleWidget()
        if #available(iOS 18.0, *) {
            ScheduleControlWidget()
        }
    }
}

/// iOS 18+ 控制中心一键打开课表。
@available(iOS 18.0, *)
struct ScheduleControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cn.edu.ubaa.schedule-control") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "ubaa://schedule")!)) {
                Label("课表", systemImage: "calendar")
            }
        }
    }
}
