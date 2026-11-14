//! 通过 Core facade 将已核对的发布目录上传到固定的公开发布分享。
use serde::Deserialize;
use std::{collections::BTreeMap, env, fs, path::Path};
use ubaa_core::facade::{
    BhpanItem, BhpanItemKind, BhpanRootKind, BhpanWriteIntent, DualLoginInput, ErrorCode,
    RoutePolicy, SecretValue, UbaaClient,
};

use ubaa_core::facade::bhpan::BhpanTransfer;

mod state;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
#[derive(Deserialize)]
struct Asset {
    name: String,
    size: u64,
}
#[derive(Deserialize)]
struct Manifest {
    version: String,
    build: String,
    assets: Vec<Asset>,
}

fn save(path: &Path, state: &BTreeMap<String, String>) -> Result<()> {
    let pending = path.with_extension("pending");
    fs::write(&pending, serde_json::to_vec(state)?)?;
    fs::rename(pending, path)?;
    Ok(())
}
async fn folder(
    client: &mut UbaaClient,
    parent: &BhpanItem,
    name: &str,
    state: &mut BTreeMap<String, String>,
    path: &Path,
) -> Result<BhpanItem> {
    let key = format!("directory/{name}");
    let matches: Vec<_> = client
        .bhpan_list(&parent.handle)
        .await?
        .items
        .into_iter()
        .filter(|item| item.name == name)
        .collect();
    if matches.len() == 1 && matches[0].kind == BhpanItemKind::Folder {
        state.insert(key, "complete".into());
        save(path, state)?;
        return Ok(matches[0].clone());
    }
    if !matches.is_empty() || state.get(&key).is_some_and(|value| value != "failed") {
        return Err("目录创建结果待核对，停止重复写入".into());
    }
    let prepared = client
        .bhpan_prepare_write(BhpanWriteIntent::CreateFolder {
            parent: parent.handle.clone(),
            name: name.into(),
        })
        .await?;
    state.insert(key.clone(), "pending".into());
    save(path, state)?;
    match client.bhpan_commit_write(&prepared.handle).await {
        Ok(_) => {
            state.insert(key, "complete".into());
            save(path, state)?;
        }
        Err(error) => {
            state.insert(
                key,
                if error.code == ErrorCode::OutcomeUnknown {
                    "unknown"
                } else {
                    "failed"
                }
                .into(),
            );
            save(path, state)?;
            return Err(error.into());
        }
    }
    client
        .bhpan_list(&parent.handle)
        .await?
        .items
        .into_iter()
        .find(|item| item.name == name && item.kind == BhpanItemKind::Folder)
        .ok_or_else(|| "创建后未读到发布目录".into())
}
async fn authenticate(client: &mut UbaaClient) -> Result<BhpanItem> {
    client.set_default_route_policy(RoutePolicy::Direct)?;
    let username = env::var("UBAA_TEST_USERNAME")?;
    let password = SecretValue::new(env::var("UBAA_TEST_PASSWORD")?);
    let login = client.interactive_login_cancellation().begin(&username)?;
    println!("准备 Direct 登录");
    client.prepare_quiet_login_for(&login).await?;
    client
        .submit_quiet_login(&login, DualLoginInput { username, password })
        .await?;
    println!("进入云盘认证");
    client.bhpan_login().await?;
    let target = env::var("UBAA_BHPAN_TARGET")?;
    println!("读取个人授权目录");
    let roots = client.bhpan_roots(BhpanRootKind::All).await?;
    let mut parents = roots.items;
    let parent = loop {
        let mut matches = Vec::new();
        for item in parents {
            let locator = client.bhpan_item_locator(&item.handle)?;
            if target == locator || target.starts_with(&(locator.clone() + "/")) {
                matches.push((item, locator));
            }
        }
        if matches.len() != 1 {
            return Err("无法从个人授权目录唯一定位发布分享".into());
        }
        let (item, locator) = matches.remove(0);
        if locator == target {
            break item;
        }
        parents = client.bhpan_list(&item.handle).await?.items;
    };
    Ok(parent)
}
async fn run() -> Result<()> {
    let directory = env::args().nth(1).ok_or("缺少发布目录")?;
    let inspect = directory == "--inspect";
    let base = env::var("UBAA_PUBLISH_STATE").unwrap_or_else(|_| "/var/lib/ubaa/bhpan".into());
    fs::create_dir_all(&base)?;
    let mut client = UbaaClient::open(Path::new(&base).join("session"))?;
    let parent = authenticate(&mut client).await?;
    if inspect {
        println!("Direct 登录成功，已定位可写授权的现有发布目录");
        return Ok(());
    }
    let directory = Path::new(&directory);
    let manifest: Manifest = serde_json::from_slice(&fs::read(directory.join("release.json"))?)?;
    UbaaClient::validate_bhpan_name(&manifest.version)?;
    if !manifest.build.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err("无效构建号".into());
    }
    let state_path = Path::new(&base).join(format!("{}-{}.json", manifest.version, manifest.build));
    let mut state = if state_path.exists() {
        serde_json::from_slice(&fs::read(&state_path)?)?
    } else {
        BTreeMap::new()
    };
    let version = folder(
        &mut client,
        &parent,
        &format!("v{}", manifest.version),
        &mut state,
        &state_path,
    )
    .await?;
    let build = folder(
        &mut client,
        &version,
        &manifest.build,
        &mut state,
        &state_path,
    )
    .await?;
    let mut assets = manifest.assets;
    assets.push(Asset {
        name: "release.json".into(),
        size: fs::metadata(directory.join("release.json"))?.len(),
    });
    upload_assets(
        &mut client,
        directory,
        &build,
        assets,
        &mut state,
        &state_path,
    )
    .await?;
    Ok(())
}
async fn upload_assets(
    client: &mut UbaaClient,
    directory: &Path,
    build: &BhpanItem,
    assets: Vec<Asset>,
    state: &mut BTreeMap<String, String>,
    state_path: &Path,
) -> Result<()> {
    for asset in assets {
        UbaaClient::validate_bhpan_name(&asset.name)?;
        let existing = client
            .bhpan_list(&build.handle)
            .await?
            .items
            .into_iter()
            .find(|item| item.name == asset.name);
        let previous = state.get(&asset.name).map(String::as_str);
        if state::skip(
            previous,
            existing.as_ref().map_or(state::Existing::Missing, |item| {
                item.bytes
                    .map_or(state::Existing::Folder, state::Existing::File)
            }),
            asset.size,
        )? {
            continue;
        }
        let prepared = client
            .bhpan_prepare_upload(
                &build.handle,
                directory.join(&asset.name),
                &asset.name,
                BhpanTransfer::new(),
            )
            .await?;
        state.insert(asset.name.clone(), "pending".into());
        save(state_path, state)?;
        match client.bhpan_commit_write(&prepared.handle).await {
            Ok(_) => {
                state.insert(asset.name.clone(), "complete".into());
                save(state_path, state)?;
            }
            Err(error) => {
                state.insert(
                    asset.name.clone(),
                    if error.code == ErrorCode::OutcomeUnknown {
                        "unknown"
                    } else {
                        "failed"
                    }
                    .into(),
                );
                save(state_path, state)?;
                return Err(error.into());
            }
        }
        let verified = client
            .bhpan_list(&build.handle)
            .await?
            .items
            .into_iter()
            .any(|item| item.name == asset.name && item.bytes == Some(asset.size));
        if !verified {
            return Err("云盘上传后文件长度核对失败".into());
        }
        println!("云盘文件已核对：{}", asset.name);
    }
    Ok(())
}
#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        if let Some(core) = error.downcast_ref::<ubaa_core::facade::UbaaError>() {
            eprintln!("云盘发布失败：{:?}", core.code);
        } else {
            eprintln!("云盘发布失败：配置、文件或分发状态需要检查");
        }
        std::process::exit(1);
    }
}
