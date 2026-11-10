//! 先比较 `SemVer` 的优先级，再比较发行构建号。

use std::cmp::Ordering;

use super::types::valid_app_version;

pub(super) fn valid_release_version(version: &str) -> bool {
    valid_app_version(version) && !version.contains('-')
}

/// 调用方传入已通过应用版本白名单的值。数字按长度及字节比较，不受整数位宽限制。
pub(super) fn compare_versions(left: &str, right: &str) -> Ordering {
    let left = Version::split(left);
    let right = Version::split(right);
    left.core
        .split('.')
        .map(Number)
        .cmp(right.core.split('.').map(Number))
        .then_with(|| match (left.pre, right.pre) {
            (None, None) => Ordering::Equal,
            (None, Some(_)) => Ordering::Greater,
            (Some(_), None) => Ordering::Less,
            (Some(left), Some(right)) => left
                .split('.')
                .map(identifier)
                .cmp(right.split('.').map(identifier)),
        })
        .then_with(|| Number(left.build).cmp(&Number(right.build)))
}

struct Version<'a> {
    core: &'a str,
    pre: Option<&'a str>,
    build: &'a str,
}

impl<'a> Version<'a> {
    fn split(value: &'a str) -> Self {
        let (version, build) = value.split_once('+').unwrap_or((value, "0"));
        let (core, pre) = version
            .split_once('-')
            .map_or((version, None), |(core, pre)| (core, Some(pre)));
        Self { core, pre, build }
    }
}

#[derive(Ord, PartialOrd, Eq, PartialEq)]
enum Identifier<'a> {
    Numeric(Number<'a>),
    Text(&'a str),
}

fn identifier(value: &str) -> Identifier<'_> {
    if value.bytes().all(|byte| byte.is_ascii_digit()) {
        Identifier::Numeric(Number(value))
    } else {
        Identifier::Text(value)
    }
}

struct Number<'a>(&'a str);

impl Ord for Number<'_> {
    fn cmp(&self, other: &Self) -> Ordering {
        let left = self.0.trim_start_matches('0');
        let right = other.0.trim_start_matches('0');
        left.len().cmp(&right.len()).then_with(|| left.cmp(right))
    }
}

impl PartialOrd for Number<'_> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for Number<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other).is_eq()
    }
}

impl Eq for Number<'_> {}
