use serde::{Deserialize, Serialize};

/// 客户端所有请求使用的网络路线。
#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionMode {
    /// 直接访问上游服务。
    Direct,
    /// 通过北航 `WebVPN` 网关访问上游服务。
    WebVpn,
}

/// 用户可选择的路线策略。`Auto` 在 Core 内部解析，宿主无需选择具体连接模式。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RoutePolicy {
    /// 根据当前校园网关可达性信号和功能矩阵解析。
    #[default]
    Auto,
    /// 使用上游直连路线。
    Direct,
    /// 使用北航 `WebVPN` 网关路线。
    WebVpn,
}

/// 注册到路由矩阵中的只读功能名称。
#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ReadonlyFeature {
    /// 博雅课程只读查询。
    Bykc,
    /// 场馆预约只读查询。
    Cgyy,
    /// 图书馆座位只读查询。
    LibBook,
    /// 阳光打卡只读查询。
    Ygdk,
    /// 课堂签到状态查询。
    Signin,
    /// 课表和教学周操作。
    Schedule,
    /// 考试安排。
    Exam,
    /// 成绩列表操作。
    Grades,
    /// 空闲教室查询。
    Classroom,
    /// SPOC 作业查询。
    Spoc,
    /// 希冀作业查询。
    Judge,
    /// 教学评教查询。
    Evaluation,
}

impl ReadonlyFeature {
    /// 稳定的配置键。
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Bykc => "bykc",
            Self::Cgyy => "cgyy",
            Self::LibBook => "libbook",
            Self::Ygdk => "ygdk",
            Self::Signin => "signin",
            Self::Schedule => "schedule",
            Self::Exam => "exam",
            Self::Grades => "grades",
            Self::Classroom => "classroom",
            Self::Spoc => "spoc",
            Self::Judge => "judge",
            Self::Evaluation => "evaluation",
        }
    }
}
