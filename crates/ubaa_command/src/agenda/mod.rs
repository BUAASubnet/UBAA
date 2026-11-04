//! 使用宿主已捕获的共享日程和缓存句柄，不接触账号材料或网络客户端。
pub(crate) mod format;
#[cfg(test)]
mod tests;
use serde::Serialize;
pub(crate) type LocalResult<T> = Result<T, LocalError>;
/// 只暴露稳定错误类别，不携带路径、身份和原生安全存储诊断。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LocalError {
    RegistrationRequired,
    MaterialUnavailable,
    MaterialCorrupt,
    Storage,
    StaleIdentity,
    CacheKeyMissing,
    CacheMissing,
    CacheCorrupt,
    AgendaCorrupt,
    InvalidInput,
    NotFound,
}
impl LocalError {
    pub(crate) const fn message(self) -> &'static str {
        match self {
            Self::RegistrationRequired => "本机日程尚未登记活动账号，请先显式登录",
            Self::MaterialUnavailable => "本机账号安全材料不可用",
            Self::MaterialCorrupt => "本机账号安全材料缺失或损坏，已保留原文件",
            Self::Storage => "本机私有目录或存储不可用",
            Self::StaleIdentity => "本机账号身份能力已失效",
            Self::CacheKeyMissing => "学校缓存密钥缺失，本机日程仍可独立读取",
            Self::CacheMissing => "当前账号尚无可用学校缓存",
            Self::CacheCorrupt => "学校缓存无法校验，已停止合并",
            Self::AgendaCorrupt => "本机日程无法读取，已保留原文件",
            Self::InvalidInput => "本机日程参数无效",
            Self::NotFound => "本机日程事项不存在",
        }
    }
    pub(crate) const fn exit(self) -> i32 {
        match self {
            Self::InvalidInput => 2,
            Self::RegistrationRequired | Self::StaleIdentity => 3,
            _ => 7,
        }
    }
}

mod execute;
pub use execute::{SharedAgendaResult, execute_shared_agenda};
pub(crate) use execute::{confirmed, input_path, validate_arguments, validate_input};

pub fn render_agenda_error(
    json: bool,
    operation: &str,
    error: LocalError,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> i32 {
    format::render(json, operation, Err(error), stdout, stderr)
}
