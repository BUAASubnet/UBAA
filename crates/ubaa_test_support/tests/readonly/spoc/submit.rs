use super::files::{Step, client, login, step};
use serde_json::{Value, json};
use ubaa_core::facade::{ErrorCode, SpocSubmitAction, bhpan::BhpanTransfer};
use ubaa_test_support::HttpMethod;

const UPLOAD: &str = "inco-filesystem/fileManagerSystem/uploadFile";
const MERGE: &str = "inco-filesystem/fileManagerSystem/mergeFile";
const SUBMIT: &str = "spocnewht/kczy/submitKcz2";
const RECORD: &str = "spocnewht/kczy/queryXsSubmitKczyInfo?kczyid=work";
const NAME: &str = "练习 A.PDF";
const ENCODED: &str = "%E7%BB%83%E4%B9%A0+A.PDF";
const MD5: &str = "618d1ad46df3c7ab8fe5fe33063089fa";
fn item(path: &str, vpn: bool, data: &Value) -> Step {
    step(path, vpn, 200, "application/json", &data.to_string())
}
fn action() -> SpocSubmitAction {
    SpocSubmitAction {
        assignment_id: "work".into(),
        course_id: "course".into(),
        allowed_extensions: vec![".pdf".into()],
        max_submissions: None,
        due_time: None,
        late_submission_deadline: None,
    }
}
fn preflight(vpn: bool, id: &str, modes: &str) -> Vec<Step> {
    let mut script = login(vpn, "fixture");
    for (path, data) in [
        ("spocnewht/inco/ht/queryOne", json!({"mrxq":"term"})),
        (
            "spocnewht/jxkj/queryKclb?kcmc=&xnxq=term",
            json!([{"kcid":"course","kcmc":"合成课"}]),
        ),
        (
            "spocnewht/inco/ht/queryListByPage",
            json!({"list":[{"zyid":"work","zymc":"练习","sskcid":"course"}]}),
        ),
        (
            "spocnewht/kczy/queryKczyInfoByid?id=work",
            json!({"id":id,"zymc":"练习","sskcid":"course","bhtjlx":modes,"zylx":"1","xzwjlx":".pdf","zyjzsj":"2020-01-01 10:00:00","sfcjzy":"1","cjzysj":"2020-01-02 10:00:00"}),
        ),
    ] {
        script.push(item(path, vpn, &json!({"code":200,"content":data})));
    }
    if id == "work" {
        script.push(item(RECORD, vpn, &json!({"code":200,"content":null})));
    }
    script
}

#[tokio::test]
async fn 文件校验大小摘要和预检资格变化均不发出写请求() {
    for case in [
        "缺失",
        "空",
        "超限",
        "扩展名",
        "变化",
        "摘要变化",
        "标识",
        "方式",
    ] {
        let (mut api, transport, root) = client(
            preflight(
                false,
                if case == "标识" { "other" } else { "work" },
                if case == "方式" { "1" } else { "5" },
            ),
            false,
        );
        let path = root.join(if case == "扩展名" {
            "练习.zip"
        } else {
            NAME
        });
        match case {
            "缺失" => {}
            "空" => std::fs::write(&path, []).unwrap(),
            "超限" => std::fs::File::create(&path)
                .unwrap()
                .set_len(100 * 1024 * 1024 + 1)
                .unwrap(),
            _ => std::fs::write(&path, b"abc").unwrap(),
        }
        let prepared = api
            .prepare_spoc_submit_assignment(&action(), &path, BhpanTransfer::new())
            .await;
        if matches!(case, "变化" | "摘要变化") {
            let prepared = prepared.unwrap().data;
            let old = std::fs::metadata(&path).unwrap().modified().unwrap();
            std::fs::write(
                &path,
                if case == "变化" {
                    b"abcd".as_slice()
                } else {
                    b"abd"
                },
            )
            .unwrap();
            std::fs::OpenOptions::new()
                .write(true)
                .open(&path)
                .unwrap()
                .set_modified(old)
                .unwrap();
            assert_eq!(
                api.confirm_spoc_submit_assignment(prepared)
                    .await
                    .unwrap_err()
                    .error
                    .code,
                ErrorCode::InvalidInput
            );
        } else {
            assert!(prepared.is_err(), "{case}");
        }
        transport.assert_exhausted();
    }
}

#[tokio::test]
async fn 分片恢复认证与最终单发后只读核对() {
    for case in [
        "秒传",
        "缺ID",
        "续传",
        "刷新",
        "第二片失败",
        "上传认证失败",
        "合并失败",
        "超时匹配",
        "超时不匹配",
        "回查失败",
        "坏响应",
        "非200",
        "明确拒绝",
    ] {
        for vpn in [false, true] {
            let large = matches!(case, "续传" | "第二片失败");
            let size = if large { 4_096_001 } else { 3 };
            let hash = if large {
                MD5
            } else {
                "900150983cd24fb0d6963f7d28e17f72"
            };
            let mut script = upload_script(case, vpn, large, size, hash);
            let (sent, submit_url) = submit_script(case, vpn, &mut script);
            let (mut api, transport, root) = client(script, vpn);
            if case.starts_with("超时") {
                transport.timeout_once(submit_url);
            }
            let path = root.join(NAME);
            let bytes = if large {
                [vec![b'A'; 2_048_000], vec![b'B'; 2_048_001]].concat()
            } else {
                b"abc".to_vec()
            };
            std::fs::write(&path, bytes).unwrap();
            let prepared = api
                .prepare_spoc_submit_assignment(&action(), &path, BhpanTransfer::new())
                .await
                .unwrap()
                .data;
            assert_eq!(prepared.summary().past_due, Some(true));
            assert_eq!(prepared.summary().byte_len, size);
            assert_eq!(prepared.summary().submission_count, Some(0));
            let result = api.confirm_spoc_submit_assignment(prepared).await;
            match case {
                "超时不匹配" | "回查失败" => {
                    assert_eq!(result.unwrap_err().error.code, ErrorCode::OutcomeUnknown);
                }
                "明确拒绝" => assert_eq!(
                    result.unwrap_err().error.private_display_message(),
                    Some("提交已关闭")
                ),
                _ if !sent => assert_ne!(result.unwrap_err().error.code, ErrorCode::OutcomeUnknown),
                _ => {
                    let receipt = result.unwrap().data;
                    assert_eq!(receipt.file_name, NAME);
                    assert_eq!(receipt.file_id, "file");
                    assert_eq!(receipt.submitted_at.as_deref(), Some("2026-01-02 10:00:00"));
                }
            }
            check_requests(&transport.requests(), case, vpn, sent, hash, size);
            transport.assert_exhausted();
        }
    }
}

fn upload_script(case: &str, vpn: bool, large: bool, size: u64, hash: &str) -> Vec<Step> {
    let count = if large { 2 } else { 1 };
    let first = if large { 2_048_000 } else { 3 };
    let probe = format!(
        "{UPLOAD}?chunkNumber=1&chunkSize=2048000&currentChunkSize={first}&totalSize={size}&identifier={hash}&filename={ENCODED}&relativePath={ENCODED}&totalChunks={count}"
    );
    let mut script = preflight(vpn, "work", "5");
    if case == "刷新" {
        script.push(step(&probe, vpn, 403, "application/json", r#"{"code":0}"#));
        script.extend(login(vpn, "fresh"));
    }
    let fast = !matches!(
        case,
        "续传" | "第二片失败" | "上传认证失败" | "合并失败" | "刷新"
    );
    script.push(item(
        &probe,
        vpn,
        &if case == "缺ID" {
            json!({"mc":true,"data":{}})
        } else if fast {
            json!({"mc":true,"data":{"id":"file"}})
        } else {
            json!({"mc":false,"data":if case=="续传"{json!([1])}else{Value::Null}})
        },
    ));
    if !fast {
        if case == "第二片失败" {
            script.push(item(UPLOAD, vpn, &json!({"mc":false,"data":null})));
        }
        script.push(step(
            UPLOAD,
            vpn,
            match case {
                "第二片失败" => 500,
                "上传认证失败" => 403,
                _ => 200,
            },
            "application/json",
            if case == "上传认证失败" {
                r#"{"code":0}"#
            } else {
                r#"{"mc":false,"data":null}"#
            },
        ));
        if !matches!(case, "第二片失败" | "上传认证失败") {
            script.push(item(
                MERGE,
                vpn,
                &if case == "合并失败" {
                    json!({})
                } else {
                    json!({"id":"file"})
                },
            ));
        }
    }
    script
}
fn submit_script(case: &str, vpn: bool, script: &mut Vec<Step>) -> (bool, String) {
    let sent = !matches!(case, "第二片失败" | "上传认证失败" | "合并失败" | "缺ID");
    let mut submit_url = String::new();
    if sent {
        let entry = step(
            SUBMIT,
            vpn,
            if case == "非200" { 503 } else { 200 },
            "application/json",
            match case {
                "坏响应" => "<html>",
                "明确拒绝" => r#"{"code":1,"msg":"提交已关闭"}"#,
                _ => r#"{"code":200,"msg":"操作成功"}"#,
            },
        );
        submit_url.clone_from(&entry.0);
        script.push(entry);
        if case != "明确拒绝" {
            script.push(step(RECORD,vpn,if case=="回查失败"{503}else{200},"application/json",&json!({"code":200,"content":{"tjzt":"1","scwjid":if case=="超时不匹配"{"old"}else{"file"},"tjsj":"2026-01-02 10:00:00"}}).to_string()));
        }
    }
    (sent, submit_url)
}
fn check_requests(
    requests: &[ubaa_test_support::HttpRequest],
    case: &str,
    vpn: bool,
    sent: bool,
    hash: &str,
    size: u64,
) {
    assert_eq!(
        requests
            .iter()
            .filter(|req| req.url.ends_with("/submitKcz2"))
            .count(),
        usize::from(sent)
    );
    for req in requests {
        if req.url.contains("fileManagerSystem/") {
            assert!(!req.headers.contains_key("RoleCode"));
            if !vpn {
                assert!(!req.headers.contains_key("Cookie"));
            }
            assert!(req.headers.contains_key("Token"));
        }
        if req.url.ends_with("/submitKcz2") {
            assert_eq!(req.body,format!("kczyid=work&tjfs=5&scwjid=file&scwjid_name={ENCODED}&tjlx=5&ytjcs=2&sskcid=course").as_bytes());
        }
        if req.url.ends_with("/mergeFile") {
            assert_eq!(
                req.body,
                format!("identifier={hash}&filename={ENCODED}&totalSize={size}").as_bytes()
            );
        }
        if req.url.ends_with("/uploadFile") && req.method == HttpMethod::Post {
            let body = std::str::from_utf8(&req.body).unwrap();
            let mut remaining = body;
            for field in [
                "chunkNumber",
                "chunkSize",
                "currentChunkSize",
                "totalSize",
                "identifier",
                "filename",
                "relativePath",
                "totalChunks",
                "file",
            ] {
                remaining = remaining
                    .split_once(&format!("name=\"{field}\""))
                    .unwrap()
                    .1;
            }
            assert!(remaining.starts_with(&format!(
                "; filename=\"{NAME}\"\r\nContent-Type: application/pdf\r\n\r\n"
            )));
            if case == "续传" {
                assert!(body.contains("name=\"chunkNumber\"\r\n\r\n2\r\n"));
                assert!(remaining.contains(&"B".repeat(2_048_001)));
            }
        }
    }
}
