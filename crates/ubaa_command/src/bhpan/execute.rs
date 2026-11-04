use super::{BhpanEntry, BhpanOutput, BhpanPreparedInput, BhpanShareEntry, navigation as n};
use crate::{BhpanArgs, BhpanCommand as C, BhpanRecycleCommand as R, BhpanShareCommand as S};
use ubaa_core::facade::{BhpanItem, BhpanItemKind, BhpanListRange, BhpanPage, BhpanWriteIntent};
use ubaa_core::facade::{Result, Routed, RoutedError, RoutedResult, UbaaClient};

/// 只消费本次 Core 读取签发的目标，返回同一 Core 作出的真实路线决策。
/// # Errors
/// 本地输入、路线、上游或发送结果未知时保留稳定错误。
pub async fn execute_bhpan(
    client: &mut UbaaClient,
    args: &BhpanArgs,
    input: &BhpanPreparedInput,
) -> RoutedResult<BhpanOutput> {
    let resolution = client.resolve_bhpan_route()?.resolution;
    input.check_file().map_err(|error| RoutedError {
        error,
        resolution: Some(resolution),
    })?;
    let data = execute(client, args, input)
        .await
        .map_err(|error| RoutedError {
            error,
            resolution: Some(resolution),
        })?;
    Ok(Routed { data, resolution })
}
fn entries(client: &mut UbaaClient, page: BhpanPage) -> Result<BhpanOutput> {
    Ok(BhpanOutput::Entries {
        items: page
            .items
            .into_iter()
            .map(|item| BhpanEntry::from_item(client, item))
            .collect::<Result<_>>()?,
        range: page.range,
    })
}
async fn shares(
    client: &mut UbaaClient,
    values: Vec<ubaa_core::facade::BhpanShare>,
) -> Result<BhpanOutput> {
    let mut result = vec![];
    for value in values {
        result.push(BhpanShareEntry::from_share(client, value).await?);
    }
    Ok(BhpanOutput::Shares { shares: result })
}
async fn commit(client: &mut UbaaClient, intent: BhpanWriteIntent) -> Result<BhpanOutput> {
    let prepared = client.bhpan_prepare_write(intent).await?;
    receipt(client, &prepared.handle).await
}
async fn receipt(client: &mut UbaaClient, handle: &str) -> Result<BhpanOutput> {
    let receipt = client.bhpan_commit_write(handle).await?;
    let item = receipt
        .item
        .map(|item| BhpanEntry::from_item(client, item))
        .transpose()?;
    let share = match receipt.share {
        Some(share) => Some(BhpanShareEntry::from_share(client, share).await?),
        None => None,
    };
    Ok(BhpanOutput::Write { item, share })
}
#[allow(clippy::too_many_lines)]
async fn execute(
    client: &mut UbaaClient,
    args: &BhpanArgs,
    input: &BhpanPreparedInput,
) -> Result<BhpanOutput> {
    let intent = match &args.command {
        C::Login => {
            client.bhpan_login().await?;
            return Ok(BhpanOutput::Login);
        }
        C::Roots => {
            let page = client.bhpan_roots(args.root.into()).await?;
            return entries(client, page);
        }
        C::List { path } => {
            let target = n::personal_path(client, args, path).await?;
            let page = client.bhpan_list(&target.handle).await?;
            return entries(client, page);
        }
        C::Stat { path } => {
            let target = n::personal_path(client, args, path).await?;
            let size = client.bhpan_size(&target.handle).await?;
            return Ok(BhpanOutput::Stat {
                item: BhpanEntry::from_item(client, target)?,
                size,
            });
        }
        C::SuggestName { parent, name } => {
            let target = n::personal_path(client, args, parent).await?;
            return Ok(BhpanOutput::SuggestedName {
                name: client.bhpan_suggest_name(&target.handle, name).await?,
            });
        }
        C::Mkdir { parent, name, .. } => BhpanWriteIntent::CreateFolder {
            parent: n::personal_path(client, args, parent).await?.handle,
            name: name.clone(),
        },
        C::Rename { path, name, .. } => BhpanWriteIntent::Rename {
            item: n::personal_path(client, args, path).await?.handle,
            name: name.clone(),
        },
        C::Move {
            path, destination, ..
        }
        | C::Copy {
            path, destination, ..
        } => {
            let item = n::personal_path(client, args, path).await?.handle;
            let destination = n::personal_path(client, args, destination).await?.handle;
            if matches!(&args.command, C::Move { .. }) {
                BhpanWriteIntent::Move { item, destination }
            } else {
                BhpanWriteIntent::Copy { item, destination }
            }
        }
        C::Delete { path, .. } => BhpanWriteIntent::Recycle {
            item: n::personal_path(client, args, path).await?.handle,
        },
        C::Recycle { command } => match command {
            R::List => {
                let page = client.bhpan_recycle().await?;
                return entries(client, page);
            }
            R::Restore { selector, .. } => BhpanWriteIntent::Restore {
                item: n::recycle_target(client, selector).await?.handle,
            },
            R::DeleteForever { selector, .. } => BhpanWriteIntent::DeleteForever {
                item: n::recycle_target(client, selector).await?.handle,
            },
        },
        C::Share { command } => match command {
            S::History => {
                let values = client.bhpan_share_history().await?;
                return shares(client, values).await;
            }
            S::Records { path } => {
                let item = n::personal_path(client, args, path).await?;
                let values = client.bhpan_share_records(&item.handle).await?;
                return shares(client, values).await;
            }
            S::Create { path, settings, .. } => BhpanWriteIntent::CreateShare {
                item: n::personal_path(client, args, path).await?.handle,
                settings: settings.settings(input.password.clone()),
            },
            S::Update { link, settings, .. } => BhpanWriteIntent::UpdateShare {
                share: n::share_target(client, link).await?,
                settings: settings.settings(input.password.clone()),
            },
            S::Cancel { link, .. } => BhpanWriteIntent::CancelShare {
                share: n::share_target(client, link).await?,
            },
            S::Open { link, path, .. } => {
                let item = n::shared_path(client, link, path, input.password.clone()).await?;
                if item.kind == BhpanItemKind::Folder {
                    let page = client.bhpan_list(&item.handle).await?;
                    return entries(client, page);
                }
                return entries(
                    client,
                    BhpanPage {
                        items: vec![item],
                        range: BhpanListRange::Unknown,
                        route: ubaa_core::facade::ConnectionMode::Direct,
                        fetched_at: 0,
                    },
                );
            }
            S::Save {
                link,
                path,
                destination,
                ..
            } => BhpanWriteIntent::Copy {
                item: n::shared_path(client, link, path, input.password.clone())
                    .await?
                    .handle,
                destination: n::personal_path(client, args, destination).await?.handle,
            },
        },
        C::UploadFast {
            parent, file, name, ..
        } => {
            let parent = n::personal_path(client, args, parent).await?;
            let transfer = TransferTask(ubaa_core::facade::bhpan::BhpanTransfer::new());
            let prepared = client
                .bhpan_prepare_fast_upload(&parent.handle, file.clone(), name, transfer.0.clone())
                .await?;
            return receipt(client, &prepared.handle).await;
        }
        C::DownloadPrepare { paths } => {
            let root = n::root(client, args).await?;
            let mut handles = vec![];
            for path in paths {
                let item: BhpanItem = n::descend(client, root.clone(), path).await?;
                handles.push(item.handle);
            }
            return Ok(BhpanOutput::DownloadPreparation {
                preparation: client
                    .bhpan_download_preparation(&handles, "download")
                    .await?,
            });
        }
    };
    commit(client, intent).await
}

struct TransferTask(ubaa_core::facade::bhpan::BhpanTransfer);
impl Drop for TransferTask {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
