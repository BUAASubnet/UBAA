use super::models::{
    BridgeBhpanCapability, BridgeBhpanItem, BridgeBhpanItemKind, BridgeBhpanListRange,
    BridgeBhpanMutationKind, BridgeBhpanPage, BridgeBhpanPermission, BridgeBhpanRootKind,
    BridgeBhpanScope, BridgeBhpanShare, BridgeBhpanShareSettings, BridgeBhpanWrite,
};
use ubaa_core::facade as c;

macro_rules! enums {
    ($b:ident,$c:ident,$($v:ident),+) => {
        impl From<$b> for c::$c { fn from(v:$b)->Self {match v { $($b::$v=>Self::$v,)+ }} }
        impl From<c::$c> for $b { fn from(v:c::$c)->Self {match v { $(c::$c::$v=>Self::$v,)+ }} }
    }
}
enums!(
    BridgeBhpanRootKind,
    BhpanRootKind,
    All,
    Personal,
    Shared,
    Department,
    Group
);
enums!(BridgeBhpanItemKind, BhpanItemKind, File, Folder);
enums!(
    BridgeBhpanScope,
    BhpanScope,
    Personal,
    ReceivedShare,
    Recycle
);
enums!(BridgeBhpanListRange, BhpanListRange, Unknown, FirstHundred);
enums!(
    BridgeBhpanPermission,
    BhpanPermission,
    Create,
    Modify,
    Download,
    Preview,
    Display
);
impl From<c::BhpanItem> for BridgeBhpanItem {
    fn from(i: c::BhpanItem) -> Self {
        Self {
            handle: i.handle,
            name: i.name,
            kind: i.kind.into(),
            scope: i.scope.into(),
            bytes: i.bytes,
            created_at: i.created_at,
            modified_at: i.modified_at,
        }
    }
}
impl From<c::BhpanPage> for BridgeBhpanPage {
    fn from(p: c::BhpanPage) -> Self {
        Self {
            items: p.items.into_iter().map(Into::into).collect(),
            range: p.range.into(),
            route: p.route.into(),
            fetched_at: p.fetched_at,
        }
    }
}
impl From<c::BhpanShare> for BridgeBhpanShare {
    fn from(s: c::BhpanShare) -> Self {
        Self {
            handle: s.handle,
            title: s.title,
            expires_at: s.expires_at,
            password_required: s.password_required,
            limited_times: s.limited_times,
            permissions: s.permissions.into_iter().map(Into::into).collect(),
            can_update: s.can_update,
        }
    }
}
impl From<BridgeBhpanShareSettings> for c::BhpanShareSettings {
    fn from(s: BridgeBhpanShareSettings) -> Self {
        Self {
            title: s.title,
            expires_at: s.expires_at,
            password: c::SecretValue::new(s.password),
            limited_times: s.limited_times,
            permissions: s.permissions.into_iter().map(Into::into).collect(),
        }
    }
}
impl TryFrom<BridgeBhpanWrite> for c::BhpanWriteIntent {
    type Error = c::UbaaError;
    fn try_from(w: BridgeBhpanWrite) -> Result<Self, Self::Error> {
        let required = |v: Option<String>| {
            v.filter(|s| !s.is_empty())
                .ok_or_else(|| c::UbaaError::invalid_input("云盘操作输入缺失"))
        };
        let settings = || {
            w.settings
                .ok_or_else(|| c::UbaaError::invalid_input("分享设置缺失"))
                .map(Into::into)
        };
        Ok(match w.kind {
            BridgeBhpanMutationKind::CreateFolder => Self::CreateFolder {
                parent: w.target,
                name: required(w.name)?,
            },
            BridgeBhpanMutationKind::Rename => Self::Rename {
                item: w.target,
                name: required(w.name)?,
            },
            BridgeBhpanMutationKind::Move => Self::Move {
                item: w.target,
                destination: required(w.destination)?,
            },
            BridgeBhpanMutationKind::Copy => Self::Copy {
                item: w.target,
                destination: required(w.destination)?,
            },
            BridgeBhpanMutationKind::Recycle => Self::Recycle { item: w.target },
            BridgeBhpanMutationKind::Restore => Self::Restore { item: w.target },
            BridgeBhpanMutationKind::DeleteForever => Self::DeleteForever { item: w.target },
            BridgeBhpanMutationKind::CreateShare => Self::CreateShare {
                item: w.target,
                settings: settings()?,
            },
            BridgeBhpanMutationKind::UpdateShare => Self::UpdateShare {
                share: w.target,
                settings: settings()?,
            },
            BridgeBhpanMutationKind::CancelShare => Self::CancelShare { share: w.target },
        })
    }
}

enums!(
    BridgeBhpanCapability,
    BhpanCapability,
    Available,
    Unverified,
    Unavailable
);
