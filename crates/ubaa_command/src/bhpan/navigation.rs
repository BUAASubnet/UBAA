use crate::{BhpanArgs, BhpanLibraryKind};
use ubaa_core::facade::{BhpanItem, BhpanItemKind, BhpanScope};
use ubaa_core::facade::{Result, SecretValue, UbaaClient, UbaaError};

pub(crate) fn components(path: &str) -> Result<Vec<&str>> {
    if !path.starts_with('/') || path.contains(['\\', '\0', '\r', '\n']) {
        return Err(UbaaError::invalid_input("云盘路径需要以 / 开头"));
    }
    let parts: Vec<_> = path.split('/').skip(1).filter(|s| !s.is_empty()).collect();
    for part in &parts {
        UbaaClient::validate_bhpan_name(part)?;
    }
    Ok(parts)
}
fn unique(mut items: Vec<BhpanItem>) -> Result<BhpanItem> {
    if items.len() != 1 {
        return Err(UbaaError::invalid_input(
            "本次读取范围内未找到唯一目标，请核对路径或文档库名称",
        ));
    }
    Ok(items.remove(0))
}
pub(super) async fn root(client: &mut UbaaClient, args: &BhpanArgs) -> Result<BhpanItem> {
    let page = if matches!(args.root, BhpanLibraryKind::Personal) && args.library.is_none() {
        client.bhpan_personal_root().await?
    } else {
        client.bhpan_roots(args.root.into()).await?
    };
    unique(
        page.items
            .into_iter()
            .filter(|item| args.library.as_ref().is_none_or(|name| item.name == *name))
            .collect(),
    )
}
pub(super) async fn descend(
    client: &mut UbaaClient,
    mut item: BhpanItem,
    path: &str,
) -> Result<BhpanItem> {
    for part in components(path)? {
        if item.kind != BhpanItemKind::Folder {
            return Err(UbaaError::invalid_input("路径中的对象不是目录"));
        }
        item = unique(
            client
                .bhpan_list(&item.handle)
                .await?
                .items
                .into_iter()
                .filter(|child| child.name == part)
                .collect(),
        )?;
    }
    Ok(item)
}
pub(super) async fn personal_path(
    client: &mut UbaaClient,
    args: &BhpanArgs,
    path: &str,
) -> Result<BhpanItem> {
    let root = root(client, args).await?;
    descend(client, root, path).await
}
pub(super) async fn shared_path(
    client: &mut UbaaClient,
    link: &str,
    path: &str,
    password: SecretValue,
) -> Result<BhpanItem> {
    let root = unique(client.bhpan_open_share(link, Some(password)).await?.items)?;
    descend(client, root, path).await
}
pub(super) async fn recycle_target(client: &mut UbaaClient, selector: &str) -> Result<BhpanItem> {
    let page = client.bhpan_recycle().await?;
    let mut matched = vec![];
    for item in page.items {
        if item.scope == BhpanScope::Recycle
            && (item.name == selector || client.bhpan_item_locator(&item.handle)? == selector)
        {
            matched.push(item);
        }
    }
    unique(matched)
}
pub(super) async fn share_target(client: &mut UbaaClient, link: &str) -> Result<String> {
    let mut matched = vec![];
    for share in client.bhpan_share_history().await? {
        let current = client.bhpan_share_link(&share.handle).await?;
        if current == link {
            matched.push(share.handle);
        }
    }
    if matched.len() != 1 {
        return Err(UbaaError::invalid_input(
            "本次分享历史中未找到唯一链接，请使用 history 返回的完整链接",
        ));
    }
    Ok(matched.remove(0))
}
