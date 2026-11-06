use super::*;

#[test]
fn 文件管理与回收站使用逐操作来源字段() {
    executor().block_on(async {
  for operation in 0..7 {
   let script=Script::default();let (mut client,root)=client(script.clone());let target=item(&mut client,if operation>=5 {BhpanScope::Recycle}else{BhpanScope::Personal});
   let mut dest=client.bhpan.item(&target.handle).unwrap();dest.scope=BhpanScope::Personal;dest.item.id="gns://fixture/destination".into();let destination=client.bhpan.publish(dest);
   let (intent,path,body,response):(BhpanWriteIntent,&'static str,serde_json::Value,&[u8])=match operation {
    0=>(BhpanWriteIntent::CreateFolder {parent:target.handle,name:"new".into()},"/api/efast/v1/dir/create",json!({"docid":"gns://fixture/target","name":"new","ondup":1}),br#"{"docid":"gns://fixture/new"}"#.as_slice()),
    1=>(BhpanWriteIntent::Rename {item:target.handle,name:"new".into()},"/api/efast/v1/dir/rename",json!({"docid":"gns://fixture/target","name":"new","ondup":1}),b"".as_slice()),
    2=>(BhpanWriteIntent::Move {item:target.handle,destination:destination.handle},"/api/efast/v1/dir/move",json!({"docid":"gns://fixture/target","destparent":"gns://fixture/destination","ondup":1}),br#"{"docid":"gns://fixture/moved"}"#),
    3=>(BhpanWriteIntent::Copy {item:target.handle,destination:destination.handle},"/api/efast/v1/dir/copy",json!({"docid":"gns://fixture/target","destparent":"gns://fixture/destination","ondup":1}),br#"{"docid":"gns://fixture/copied"}"#),
    4=>(BhpanWriteIntent::Recycle {item:target.handle},"/api/efast/v1/file/delete",json!({"docid":"gns://fixture/target"}),b""),
    5=>(BhpanWriteIntent::Restore {item:target.handle},"/api/efast/v1/recycle/restore",json!({"docid":"gns://fixture/target","ondup":1}),br#"{"docid":"gns://fixture/restored"}"#),
    _=>(BhpanWriteIntent::DeleteForever {item:target.handle},"/api/efast/v1/recycle/delete",json!({"docid":"gns://fixture/target"}),b""),
   };
   script.add(HttpMethod::Post,path,Some(body),response);let p=client.bhpan_prepare_write(intent).await.unwrap();client.bhpan_commit_write(&p.handle).await.unwrap();script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
  }
 });
}
#[test]
fn 分享创建更新取消保持原目标与权限且密码不进入公开结果() {
    executor().block_on(async {
  let script=Script::default();let (mut client,root)=client(script.clone());let target=item(&mut client,BhpanScope::Personal);
  let settings=BhpanShareSettings {title:"synthetic".into(),expires_at:"1970-01-01T08:00:00+08:00".into(),password:SecretValue::new("fixture-password"),keep_password:false,limited_times:-1,permissions:vec![BhpanPermission::Display,BhpanPermission::Download]};
  let body=json!({"item":{"id":"gns://fixture/target","type":"folder","allow":["display","download"]},"title":"synthetic","expires_at":"1970-01-01T08:00:00+08:00","password":"fixture-password","limited_times":-1});
  script.add(HttpMethod::Post,"/api/shared-link/v1/document/anonymous",Some(body.clone()),br#"{"id":"synthetic-share"}"#);
  let p=client.bhpan_prepare_write(BhpanWriteIntent::CreateShare {item:target.handle,settings:settings.clone()}).await.unwrap();let share=client.bhpan_commit_write(&p.handle).await.unwrap().share.unwrap();
  assert!(!serde_json::to_string(&share).unwrap().contains("fixture-password"));assert!(share.password_required);
  script.add(HttpMethod::Put,"/api/shared-link/v1/document/anonymous/synthetic-share",Some(body),b"");
  let p=client.bhpan_prepare_write(BhpanWriteIntent::UpdateShare {share:share.handle.clone(),settings}).await.unwrap();client.bhpan_commit_write(&p.handle).await.unwrap();
  script.add(HttpMethod::Delete,"/api/shared-link/v1/document/anonymous/synthetic-share",None,b"");let p=client.bhpan_prepare_write(BhpanWriteIntent::CancelShare {share:share.handle}).await.unwrap();client.bhpan_commit_write(&p.handle).await.unwrap();
  script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
 });
}
#[test]
fn 回收站保持首批范围且负统计失败() {
    executor().block_on(async {
  let script=Script::default();script.add(HttpMethod::Get,"/api/efast/v1/owned-doc-lib",None,br#"[{"id":"gns://fixture/target","name":"root"}]"#);
  script.add(HttpMethod::Post,"/api/efast/v1/recycle/list",Some(json!({"by":"time","docid":"gns://fixture/target","limit":100,"sort":"desc","start":0})),br#"{"dirs":[],"files":[]}"#);
  let (mut client,root)=client(script.clone());assert_eq!(client.bhpan_recycle().await.unwrap().range,BhpanListRange::FirstHundred);
  assert!(parse::size(br#"{"dirnum":-1,"filenum":0,"totalsize":0}"#).is_err());script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
 });
}

#[test]
fn 分享历史保留显式doc关联并支持更新_缺关联的单项记录拒绝更新() {
    executor().block_on(async {
  let script=Script::default();let (mut client,root)=client(script.clone());
  script.add(HttpMethod::Get,"/api/doc-share/v1/docs-shared-with-anyone",None,br#"{"entries":[{"doc":{"id":"gns://fixture/target","type":"folder"},"link_configs":[{"id":"history-share","title":"old","allow":["display"],"expires_at":"1970-01-01T08:00:00+08:00","password":"","limited_times":-1}]}]}"#);
  let share=client.bhpan_share_history().await.unwrap().remove(0);assert!(share.can_update);
  let settings=BhpanShareSettings {title:"new".into(),expires_at:share.expires_at.clone(),password:SecretValue::new(""),keep_password:false,limited_times:-1,permissions:vec![BhpanPermission::Display]};
  script.add(HttpMethod::Put,"/api/shared-link/v1/document/anonymous/history-share",Some(json!({"item":{"id":"gns://fixture/target","type":"folder","allow":["display"]},"title":"new","expires_at":"1970-01-01T08:00:00+08:00","password":"","limited_times":-1})),b"");
  let p=client.bhpan_prepare_write(BhpanWriteIntent::UpdateShare {share:share.handle,settings:settings.clone()}).await.unwrap();client.bhpan_commit_write(&p.handle).await.unwrap();
  let item=item(&mut client,BhpanScope::Personal);
  script.add(HttpMethod::Get,"/api/shared-link/v1/document/folder/gns%3A%2F%2Ffixture%2Ftarget?type=anonymous",None,br#"[{"id":"record-share","title":"old","item":{"allow":["display"]},"expires_at":"1970-01-01T08:00:00+08:00","password":"","limited_times":-1}]"#);
  let share=client.bhpan_share_records(&item.handle).await.unwrap().remove(0);assert!(!share.can_update);
  assert!(client.bhpan_prepare_write(BhpanWriteIntent::UpdateShare {share:share.handle,settings}).await.is_err());script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
 });
}

#[test]
fn update_share_keeps_history_password_without_public_projection() {
    executor().block_on(async {
        let script = Script::default();
        let (mut client, root) = client(script.clone());
        script.add(
            HttpMethod::Get,
            "/api/doc-share/v1/docs-shared-with-anyone",
            None,
            br#"{"entries":[{"doc":{"id":"gns://fixture/target","type":"folder"},"link_configs":[{"id":"protected-share","title":"old","allow":["display"],"expires_at":"1970-01-01T08:00:00+08:00","password":"fixture-original-password","limited_times":-1}]}]}"#,
        );
        let share = client.bhpan_share_history().await.unwrap().remove(0);
        assert!(share.password_required);

        let settings = BhpanShareSettings {
            title: "new".into(),
            expires_at: share.expires_at.clone(),
            password: SecretValue::new(""),
            keep_password: true,
            limited_times: -1,
            permissions: vec![BhpanPermission::Display],
        };
        script.add(
            HttpMethod::Put,
            "/api/shared-link/v1/document/anonymous/protected-share",
            Some(json!({
                "item":{"id":"gns://fixture/target","type":"folder","allow":["display"]},
                "title":"new",
                "expires_at":"1970-01-01T08:00:00+08:00",
                "password":"fixture-original-password",
                "limited_times":-1
            })),
            b"",
        );
        let prepared = client
            .bhpan_prepare_write(BhpanWriteIntent::UpdateShare {
                share: share.handle,
                settings,
            })
            .await
            .unwrap();
        let result = client.bhpan_commit_write(&prepared.handle).await.unwrap();
        assert!(!serde_json::to_string(&result).unwrap().contains("fixture-original-password"));
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 接收带密码分享使用临时授权浏览且另存使用双授权() {
    executor().block_on(async {
  let script=Script::default();
  let push=|method,path,body,token,response:HttpResponse|script.steps.lock().unwrap().push_back(Step {method,path,body,token,secondary:None,response:Ok(response)});
  push(HttpMethod::Get,"/api/shared-link/v1/links/synthetic-share",None,None,HttpResponse::new(200,format!("{}/api/shared-link/v1/links/synthetic-share",wire::ORIGIN),br#"{"password_required":true}"#.to_vec()));
  let mut link=HttpResponse::new(200,format!("{}/link",wire::ORIGIN),Vec::new());link.headers.insert("Set-Cookie".into(),vec!["link_token:synthetic-share=share-fixture; Path=/; Secure".into()]);
  push(HttpMethod::Post,"/link",Some(json!({"id":"synthetic-share","type":"anonymous","password_required":true,"password":"fixture-password"})),None,link);
  push(HttpMethod::Get,"/api/efast/v1/entry-item",None,Some("Bearer share-fixture"),HttpResponse::new(200,format!("{}/api/efast/v1/entry-item",wire::ORIGIN),br#"[{"id":"gns://share/root","name":"shared","created_at":"2026-11-05T00:00:00Z","modified_at":"2026-11-05T00:00:00Z"}]"#.to_vec()));
  push(HttpMethod::Post,"/api/efast/v1/dir/list",Some(json!({"by":"name","docid":"gns://share/root","sort":"asc"})),Some("Bearer share-fixture"),HttpResponse::new(200,format!("{}/api/efast/v1/dir/list",wire::ORIGIN),br#"{"dirs":[],"files":[]}"#.to_vec()));
  let (mut client,root)=client(script.clone());client.direct_runtime.set_scoped_cookie("client.oauth2_token=personal-cookie; Path=/; Secure",wire::ORIGIN).unwrap();
  let shared=client.bhpan_open_share("synthetic-share",Some(SecretValue::new("fixture-password"))).await.unwrap().items.remove(0);assert_eq!(shared.scope,BhpanScope::ReceivedShare);
  client.bhpan_list(&shared.handle).await.unwrap();
  let destination=item(&mut client,BhpanScope::Personal);
  assert!(client.bhpan_download_preparation(&[shared.handle.clone(),destination.handle.clone()],"mixed").await.is_err());
  // 个人目标的 copy 正文与来源分享的第二授权由 Core 组合。
  let source=client.bhpan.item(&shared.handle).unwrap();assert_eq!(source.token.unwrap().expose_secret(),"share-fixture");
  script.steps.lock().unwrap().push_back(Step {method:HttpMethod::Post,path:"/api/efast/v1/dir/copy",body:Some(json!({"docid":"gns://share/root","destparent":"gns://fixture/target","ondup":1})),token:Some("Bearer personal-fixture"),secondary:Some("Bearer share-fixture"),response:Ok(HttpResponse::new(200,format!("{}/api/efast/v1/dir/copy",wire::ORIGIN),br#"{"docid":"gns://fixture/copied"}"#.to_vec()))});
  let prepared=client.bhpan_prepare_write(BhpanWriteIntent::Copy {item:shared.handle,destination:destination.handle}).await.unwrap();client.bhpan_commit_write(&prepared.handle).await.unwrap();
  script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
 });
}
