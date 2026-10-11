//! 仅白名单化本地初始化原因；任何错误均不带文件路径或原始异常。
use super::client::BridgeErrorCode;
use std::fmt;
use ubaa_core::facade::{InitializationFailure, UbaaClient};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeInitializationFailure {
    Configuration,
    Session,
    ResourceBusy,
    ComponentUnavailable,
}

#[derive(Clone, Debug)]
pub struct BridgeInitializationError {
    pub code: BridgeErrorCode,
    pub failure: BridgeInitializationFailure,
}

impl fmt::Display for BridgeInitializationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "本地初始化失败：{:?}", self.failure)
    }
}
impl std::error::Error for BridgeInitializationError {}

pub(super) fn open(config_dir: &str) -> Result<UbaaClient, BridgeInitializationError> {
    if config_dir.trim().is_empty() || !std::path::Path::new(config_dir).is_absolute() {
        return Err(BridgeInitializationError {
            code: BridgeErrorCode::InvalidInput,
            failure: BridgeInitializationFailure::Configuration,
        });
    }
    std::panic::catch_unwind(|| UbaaClient::open(config_dir))
        .map_err(|_| BridgeInitializationError {
            code: BridgeErrorCode::InternalError,
            failure: BridgeInitializationFailure::ComponentUnavailable,
        })?
        .map_err(|error| BridgeInitializationError {
            code: error.code.into(),
            failure: match error.initialization_failure() {
                Some(InitializationFailure::Configuration) => {
                    BridgeInitializationFailure::Configuration
                }
                Some(InitializationFailure::Session) => BridgeInitializationFailure::Session,
                Some(InitializationFailure::ResourceBusy) => {
                    BridgeInitializationFailure::ResourceBusy
                }
                _ => BridgeInitializationFailure::ComponentUnavailable,
            },
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 配置与会话错误分类不依赖正文且不丢弃损坏材料() {
        let root = std::env::temp_dir().join(format!("ubaa-init-category-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        for (file, expected) in [
            ("config.toml", BridgeInitializationFailure::Configuration),
            ("session.json", BridgeInitializationFailure::Session),
        ] {
            let path = root.join(file);
            std::fs::write(&path, "合成损坏数据").unwrap();
            let Err(error) = open(root.to_str().unwrap()) else {
                panic!("损坏数据必须失败");
            };
            assert_eq!(error.failure, expected);
            assert!(!error.to_string().contains(root.to_str().unwrap()));
            assert_eq!(std::fs::read_to_string(&path).unwrap(), "合成损坏数据");
            std::fs::remove_file(path).unwrap();
        }
        std::fs::remove_dir_all(root).unwrap();
    }
}
