use super::*;
const FIRST: &str = "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Ftarget/sub_objects?limit=1000";
const SECOND: &str = "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Ftarget/sub_objects?limit=1000&marker=next%2B%2F%3D";
fn entry(id: &str, name: &str) -> serde_json::Value {
    json!({"id": id, "name": name, "size":5, "rev":"r", "created_at":"2026-11-05T01:00:00Z", "modified_at":"2026-11-05T02:00:00Z"})
}
#[tokio::test]
async fn 完整分页逐字复用标记并接受短页后续及一致重复条目() {
    let script = Script::default();
    let file = entry("gns://fixture/file", "one.json");
    script.add(
        HttpMethod::Get,
        FIRST,
        None,
        &serde_json::to_vec(&json!({"dirs":[],"files":[file.clone()],"next_marker":"next+/="}))
            .unwrap(),
    );
    script.add(HttpMethod::Get,SECOND,None,&serde_json::to_vec(&json!({"dirs":[],"files":[file,entry("gns://fixture/two","two.json")],"next_marker":""})).unwrap());
    let (mut client, root) = client(script.clone());
    let parent = item(&mut client, BhpanScope::Personal);
    let items = client.bhpan_list_complete(&parent.handle).await.unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].name, "one.json");
    assert_eq!(items[0].modified_at, Some(1_793_844_000));
    script.done();
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn 分页缺少结束标记或必需条目字段均拒绝且不签发部分句柄() {
    for response in [
        json!({"dirs":[],"files":[]}),
        json!({"dirs":[],"files":[],"next_marker":null}),
        json!({"dirs":[],"files":[{"id":"gns://fixture/file","name":"x"}],"next_marker":""}),
    ] {
        let script = Script::default();
        script.add(
            HttpMethod::Get,
            FIRST,
            None,
            &serde_json::to_vec(&response).unwrap(),
        );
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        assert!(client.bhpan_list_complete(&parent.handle).await.is_err());
        assert_eq!(client.bhpan.items.len(), 1);
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}
#[tokio::test]
async fn 分页标记循环冲突条目和后页网络失败均拒绝整轮() {
    for case in 0..3 {
        let script = Script::default();
        let file = entry("gns://fixture/file", "one.json");
        script.add(
            HttpMethod::Get,
            FIRST,
            None,
            &serde_json::to_vec(&json!({"dirs":[],"files":[file],"next_marker":"next+/="}))
                .unwrap(),
        );
        let response = match case {
            0 => json!({"dirs":[],"files":[],"next_marker":"next+/="}),
            1 => {
                json!({"dirs":[],"files":[entry("gns://fixture/file","changed.json")],"next_marker":""})
            }
            _ => json!({"dirs":[],"files":[],"next_marker":""}),
        };
        script.add(
            HttpMethod::Get,
            SECOND,
            None,
            &serde_json::to_vec(&response).unwrap(),
        );
        if case == 2 {
            script.status(500);
        }
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        assert!(client.bhpan_list_complete(&parent.handle).await.is_err());
        assert_eq!(client.bhpan.items.len(), 1);
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 路径缺失等待全部分页而同名歧义和中间文件明确失败() {
    use crate::domain::bhpan::BhpanPathLookup;
    for case in 0..3 {
        let script = Script::default();
        script.add(
            HttpMethod::Get,
            "/api/efast/v1/owned-doc-lib",
            None,
            br#"[{"id":"gns://fixture/target","name":"personal"}]"#,
        );
        let mut ub = entry("gns://fixture/ubaa", "UBAA");
        ub["size"] = json!(-1);
        let (dirs, files) = match case {
            0 => (vec![], vec![]),
            1 => {
                let mut other = ub.clone();
                other["id"] = json!("gns://fixture/duplicate");
                (vec![ub.clone(), other], vec![])
            }
            _ => {
                ub["size"] = json!(5);
                (vec![], vec![ub.clone()])
            }
        };
        script.add(
            HttpMethod::Get,
            FIRST,
            None,
            &serde_json::to_vec(
                &json!({"dirs":dirs,"files":files,"next_marker":if case==0{"next+/="}else{""}}),
            )
            .unwrap(),
        );
        if case == 0 {
            script.add(
                HttpMethod::Get,
                SECOND,
                None,
                &serde_json::to_vec(&json!({"dirs":[ub],"files":[],"next_marker":""})).unwrap(),
            );
            script.add(
                HttpMethod::Get,
                "/api/efast/v1/folders/gns%3A%2F%2Ffixture%2Fubaa/sub_objects?limit=1000",
                None,
                br#"{"dirs":[],"files":[],"next_marker":""}"#,
            );
        }
        let (mut client, root) = client(script.clone());
        let result = client
            .bhpan_lookup_personal_path_complete(&["UBAA".into(), "agenda_snapshots".into()])
            .await;
        if case == 0 {
            assert!(
                matches!(result,Ok(BhpanPathLookup::Missing{parent,remaining}) if parent.name=="UBAA" && remaining==["agenda_snapshots"])
            );
        } else {
            assert!(result.is_err());
        }
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}
