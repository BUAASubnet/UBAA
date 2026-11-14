//! 同一构建重跑时，只跳过已经确认成功且长度一致的文件。
use crate::Result;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Existing {
    Missing,
    File(u64),
    Folder,
}

pub(crate) fn skip(previous: Option<&str>, existing: Existing, expected: u64) -> Result<bool> {
    if previous == Some("complete") && existing == Existing::File(expected) {
        return Ok(true);
    }
    if existing != Existing::Missing || matches!(previous, Some("pending" | "unknown" | "complete"))
    {
        return Err("文件上传结果待核对，停止重复写入".into());
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::{
        Existing::{File, Folder, Missing},
        skip,
    };
    #[test]
    fn only_confirmed_same_file_is_skipped() {
        assert!(skip(Some("complete"), File(42), 42).unwrap());
        assert!(skip(Some("complete"), File(43), 42).is_err());
        assert!(skip(Some("complete"), Missing, 42).is_err());
        assert!(skip(None, Folder, 42).is_err());
        assert!(skip(None, File(42), 42).is_err());
    }
    #[test]
    fn uncertain_writes_are_not_replayed() {
        for previous in ["pending", "unknown"] {
            assert!(skip(Some(previous), Missing, 42).is_err());
            assert!(skip(Some(previous), File(42), 42).is_err());
        }
        assert!(!skip(None, Missing, 42).unwrap());
        assert!(!skip(Some("failed"), Missing, 42).unwrap());
    }
}
