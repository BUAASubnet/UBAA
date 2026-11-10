//! 同一上游域名的临时 `WebVPN` 偏好，不保存账号或请求材料。
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use super::super::types::Operation;
use crate::domain::ReadonlyFeature;

const TTL: i64 = 24 * 60 * 60;

#[derive(Default)]
pub(in crate::facade) struct DomainRoutes {
    path: Option<PathBuf>,
    expires: BTreeMap<String, i64>,
    recovery: BTreeSet<String>,
}

impl DomainRoutes {
    pub(in crate::facade) fn load(directory: &Path) -> Self {
        let path = directory.join("domain_routes.json");
        let expires = std::fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        Self {
            path: Some(path),
            expires,
            recovery: BTreeSet::new(),
        }
    }

    pub(in crate::facade) fn prefers_webvpn(&self, operation: Operation, now: i64) -> bool {
        domains(operation).iter().any(|domain| {
            self.expires
                .get(*domain)
                .is_some_and(|expires| *expires > now && *expires - now <= TTL)
        })
    }

    pub(in crate::facade) fn require_webvpn(&mut self, domain: String) {
        self.recovery.insert(domain);
    }

    pub(in crate::facade) fn needs_webvpn(&self, operation: Operation) -> bool {
        domains(operation)
            .iter()
            .any(|domain| self.recovery.contains(*domain))
    }

    pub(in crate::facade) fn remember(&mut self, domain: String, now: i64) {
        self.expires
            .retain(|_, expires| *expires > now && *expires - now <= TTL);
        self.recovery.remove(&domain);
        self.expires.insert(domain, now.saturating_add(TTL));
        self.save();
    }

    pub(in crate::facade) fn campus(&mut self) {
        self.recovery.clear();
        if !self.expires.is_empty() {
            self.expires.clear();
            self.save();
        }
    }

    fn save(&self) {
        let Some(path) = &self.path else {
            return;
        };
        let temporary = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
        let write = || -> std::io::Result<()> {
            use std::io::Write;
            let mut options = std::fs::OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let mut file = options.open(&temporary)?;
            file.write_all(&serde_json::to_vec(&self.expires)?)?;
            file.sync_all()?;
            std::fs::rename(&temporary, path)
        };
        if write().is_err() {
            let _ = std::fs::remove_file(&temporary);
            tracing::warn!("域名路线记录未保存，本次结果继续使用");
        }
    }
}

pub(in crate::facade) fn allowed(domain: &str) -> bool {
    matches!(
        domain,
        "icw.buaa.edu.cn"
            | "chaxun.icw.buaa.edu.cn"
            | "uc.buaa.edu.cn"
            | "byxt.buaa.edu.cn"
            | "gsmis.buaa.edu.cn"
            | "app.buaa.edu.cn"
            | "spoc.buaa.edu.cn"
            | "judge.buaa.edu.cn"
            | "iclass.buaa.edu.cn"
            | "i.buaa.edu.cn"
            | "ygdk.buaa.edu.cn"
            | "booking.lib.buaa.edu.cn"
            | "bykc.buaa.edu.cn"
            | "cgyy.buaa.edu.cn"
            | "it.buaa.edu.cn"
            | "zfw.buaa.edu.cn"
    )
}

fn domains(operation: Operation) -> &'static [&'static str] {
    match operation {
        Operation::User => &["uc.buaa.edu.cn"],
        Operation::Bhpan | Operation::Authentication | Operation::ConnectionRecovery => &[],
        Operation::Feature(feature) => match feature {
            ReadonlyFeature::Schedule | ReadonlyFeature::Exam | ReadonlyFeature::Grades => {
                &["byxt.buaa.edu.cn", "gsmis.buaa.edu.cn"]
            }
            ReadonlyFeature::Classroom => &["app.buaa.edu.cn"],
            ReadonlyFeature::Spoc | ReadonlyFeature::Evaluation => &["spoc.buaa.edu.cn"],
            ReadonlyFeature::Judge => &["judge.buaa.edu.cn"],
            ReadonlyFeature::Signin => &["iclass.buaa.edu.cn"],
            ReadonlyFeature::Ihome => &["i.buaa.edu.cn"],
            ReadonlyFeature::Ygdk => &["ygdk.buaa.edu.cn", "app.buaa.edu.cn"],
            ReadonlyFeature::LibBook => &["booking.lib.buaa.edu.cn"],
            ReadonlyFeature::Bykc => &["bykc.buaa.edu.cn"],
            ReadonlyFeature::Cgyy => &["cgyy.buaa.edu.cn"],
            ReadonlyFeature::Portal => &["it.buaa.edu.cn"],
            ReadonlyFeature::Network => &["zfw.buaa.edu.cn"],
            ReadonlyFeature::Finance => &["icw.buaa.edu.cn", "chaxun.icw.buaa.edu.cn"],
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 同域名共享记录且二十四小时到期或切回校园网后重新直连() {
        let mut cache = DomainRoutes::default();
        cache.remember("spoc.buaa.edu.cn".into(), 100);
        for feature in [ReadonlyFeature::Spoc, ReadonlyFeature::Evaluation] {
            assert!(cache.prefers_webvpn(Operation::Feature(feature), 100 + TTL - 1));
            assert!(!cache.prefers_webvpn(Operation::Feature(feature), 100 + TTL));
        }
        assert!(!cache.prefers_webvpn(Operation::Feature(ReadonlyFeature::Judge), 101));
        cache.campus();
        assert!(!cache.prefers_webvpn(Operation::Feature(ReadonlyFeature::Spoc), 101));
    }
}
