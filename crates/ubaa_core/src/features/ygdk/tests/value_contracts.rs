use super::*;

#[test]
fn 从回调片段查询中提取授权码() {
    assert_eq!(
        code_from_url("https://ygdk.buaa.edu.cn/#/home?code=%E5%B7%B2%E8%84%B1%E6%95%8F"),
        Some("已脱敏".into())
    );
}

#[test]
fn 空白回调授权码不会被当作可用凭据() {
    for url in [
        "https://ygdk.buaa.edu.cn/?code=",
        "https://ygdk.buaa.edu.cn/#/home?code=%20%20",
    ] {
        assert_eq!(code_from_url(url), None, "{url}");
    }
}

#[test]
fn 解码不含等号的业务令牌值() {
    assert_eq!(percent_decode("token%2Bvalue%2Ftail"), "token+value/tail");
}

#[test]
fn 阳光打卡凭据调试输出不泄露令牌() {
    let credential = YgdkCredential {
        uid: 42,
        token: "ygdk-secret-token".into(),
    };
    let rendered = format!("{credential:?}");
    assert!(!rendered.contains("ygdk-secret-token"));
}

#[test]
fn 照片调试输出只显示字节数与已校验_mime() {
    let valid = YgdkPhotoUpload {
        bytes: b"JPEG".to_vec(),
        file_name: "private-photo.jpg".into(),
        mime_type: "image/jpeg".into(),
    };
    let rendered = format!("{valid:?}");
    assert!(rendered.contains("4 bytes"));
    assert!(rendered.contains("image/jpeg"));
    assert!(!rendered.contains("private-photo.jpg"));
    assert!(!rendered.contains("JPEG"));

    let invalid = YgdkPhotoUpload {
        mime_type: "image/jpeg\r\nsecret-header".into(),
        ..valid
    };
    let rendered = format!("{invalid:?}");
    assert!(rendered.contains("[INVALID]"));
    assert!(!rendered.contains("secret-header"));
}

#[test]
fn 记录时间戳按冻结东八区格式化() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "start_time": 1_772_323_200, "end_time": 1_772_326_800}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(
        page.content[0].start_time.as_deref(),
        Some("2026-03-01 08:00")
    );
}

#[test]
fn 数字字符串时间戳同样按冻结格式化() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "start_time": "1772323200"}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(
        page.content[0].start_time.as_deref(),
        Some("2026-03-01 08:00")
    );
}

#[test]
fn 记录图片格式化字符串按单个地址保留() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "images_fmt": "https://img/one"}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(page.content[0].images, vec!["https://img/one"]);
}

#[test]
fn 记录文本原语按冻结实现转为字符串() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "item_name": 7, "place": true}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(page.content[0].item_name.as_deref(), Some("7"));
    assert_eq!(page.content[0].place.as_deref(), Some("true"));
}

#[test]
fn 阳光打卡上传正文匹配冻结_multipart_字段() {
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    let photo = YgdkPhotoUpload {
        file_name: "p.jpg".into(),
        mime_type: "image/jpeg".into(),
        bytes: b"PNG".to_vec(),
    };
    let body = String::from_utf8(build_upload_body(&credential, &photo, "b").unwrap()).unwrap();
    assert!(body.contains("name=\"uid\"\r\n\r\n7"));
    assert!(body.contains("name=\"token\"\r\n\r\ntok"));
    assert!(body.contains("name=\"file\"; filename=\"p.jpg\""));
    assert!(body.ends_with("\r\n--b--\r\n"));
}

#[test]
fn 完整上海时间被规范化为冻结_epoch与展示区间() {
    let normalized = normalize_submit_request(&valid_submit_request()).expect("规范化提交输入");

    assert_eq!(normalized.start_epoch_seconds, 1_775_001_600);
    assert_eq!(normalized.end_epoch_seconds, 1_775_005_200);
    assert_eq!(normalized.start_time, "2026-04-01 08:00");
    assert_eq!(normalized.end_time, "2026-04-01 09:00");
    assert_eq!(normalized.form_time_fmt, "2026-04-01 08:00-09:00");
}

#[test]
fn 历史上海夏令时时间按命名时区转换() {
    let mut request = valid_submit_request();
    request.start_time = "1990-07-01 08:00".into();
    request.end_time = "1990-07-01 09:00".into();

    let normalized = normalize_submit_request(&request).expect("规范化历史上海时间");

    assert_eq!(normalized.start_epoch_seconds, 646_786_800);
    assert_eq!(normalized.end_epoch_seconds, 646_790_400);
    assert_eq!(normalized.form_time_fmt, "1990-07-01 08:00-09:00");
}

#[test]
fn 分类回退会在完整列表中优先寻找标识一() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":2,"name":"普通分类"},{"classify_id":1,"name":"备用分类"}]}}"#;
    let items = r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#;
    let empty = r#"{"code":1,"result":{}}"#;

    let overview = parse_overview(classify, items, empty, empty).expect("解析 ID 1 fallback 分类");

    assert_eq!(overview.classify_id, 1);
    assert_eq!(overview.classify_name, "备用分类");
    assert_eq!(
        overview.items[0].submit_target,
        Some(YgdkSubmitTarget {
            classify_id: 1,
            item_id: 2,
        })
    );
}

#[test]
fn 只读项目展示继续丢弃畸形行而不伪造占位项() {
    let items = r#"{"code":1,"result":{"list":[null,{"name":"缺少标识"},{"item_id":3,"name":""},{"item_id":2,"name":"跑步"}]}}"#;

    let parsed = parse_items(items).expect("解析可展示项目");

    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].item_id, 2);
    assert_eq!(parsed[0].name, "跑步");
    assert_eq!(parsed[0].submit_eligibility, ActionEligibility::Unknown);
    assert!(parsed[0].submit_target.is_none());
}

#[test]
fn 项目重复时不产生可提交目标() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#;
    let items =
        r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"},{"item_id":2,"name":"健走"}]}}"#;
    let empty = r#"{"code":1,"result":{}}"#;

    let overview = parse_overview(classify, items, empty, empty).unwrap();

    assert_eq!(overview.items.len(), 2);
    assert!(overview.items.iter().all(|item| {
        item.submit_eligibility == ActionEligibility::Unknown && item.submit_target.is_none()
    }));
}

#[test]
fn 字符串数值标识不能成为可提交目标() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":"1","name":"阳光体育"}]}}"#;
    let items = r#"{"code":1,"result":{"list":[{"item_id":"2","name":"跑步"}]}}"#;
    let empty = r#"{"code":1,"result":{}}"#;

    let overview = parse_overview(classify, items, empty, empty).unwrap();

    assert_eq!(overview.items.len(), 1);
    assert_eq!(
        overview.items[0].submit_eligibility,
        ActionEligibility::Unknown
    );
    assert!(overview.items[0].submit_target.is_none());
}

#[test]
fn 非字符串名称不能成为可提交权威() {
    let empty = r#"{"code":1,"result":{}}"#;
    for (classify, items) in [
        (
            r#"{"code":1,"result":{"list":[{"classify_id":1,"name":123}]}}"#,
            r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#,
        ),
        (
            r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#,
            r#"{"code":1,"result":{"list":[{"item_id":2,"name":true}]}}"#,
        ),
    ] {
        let overview = parse_overview(classify, items, empty, empty).expect("保留安全展示结果");
        assert!(overview.items.iter().all(|item| {
            item.submit_eligibility == ActionEligibility::Unknown && item.submit_target.is_none()
        }));
    }
}

#[test]
fn 畸形项目行不会因被丢弃而授权剩余项目() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#;
    let empty = r#"{"code":1,"result":{}}"#;
    for malformed in [
        r#"{"name":"缺少标识"}"#,
        r#"{"item_id":0,"name":"零标识"}"#,
        r#"{"item_id":-1,"name":"负标识"}"#,
        r#"{"item_id":3,"name":""}"#,
    ] {
        let items = format!(
            r#"{{"code":1,"result":{{"list":[{malformed},{{"item_id":2,"name":"跑步"}}]}}}}"#
        );
        let overview = parse_overview(classify, &items, empty, empty).expect("保留安全展示结果");
        assert!(overview.items.iter().all(|item| {
            item.submit_eligibility == ActionEligibility::Unknown && item.submit_target.is_none()
        }));
    }
}

#[test]
fn 已确认成功时无效回执标识只被丢弃() {
    for body in [
        r#"{"code":1,"result":{"record_id":"7"}}"#,
        r#"{"code":1,"result":{"record_id":0}}"#,
        r#"{"code":1,"result":{"record_id":-1}}"#,
    ] {
        let result = parse_submit_result(body).expect("业务成功不得被可选回执标识覆盖");
        assert!(result.success);
        assert_eq!(result.message, "阳光打卡已提交");
        assert_eq!(result.record_id, None);
    }
}

#[test]
fn 最终响应的所有未确认形状都归一为固定未知结果() {
    for (case, body) in [
        ("missing-code", r#"{"result":{}}"#),
        ("string-code", r#"{"code":"1","result":{}}"#),
        ("non-success", r#"{"code":500,"msg":"secret raw"}"#),
        ("missing-result", r#"{"code":1}"#),
        ("null-result", r#"{"code":1,"result":null}"#),
        ("array-result", r#"{"code":1,"result":[]}"#),
        ("scalar-result", r#"{"code":1,"result":7}"#),
        ("non-json", "secret raw"),
        ("array-root", r#"[{"code":1,"result":{}}]"#),
    ] {
        let error = parse_submit_result(body).expect_err("歧义 final 响应不能确认成功");
        assert_eq!(
            error.code,
            crate::error::ErrorCode::OutcomeUnknown,
            "{case}"
        );
        assert_eq!(error.kind, crate::error::ErrorKind::Upstream, "{case}");
        assert!(!error.retryable, "{case}");
        assert_eq!(
            error.message, "阳光打卡提交结果未知，请刷新概览和记录后核对",
            "{case}"
        );
        assert!(!error.message.contains("secret"), "{case}");
        assert!(!error.message.contains('\n'), "{case}");
    }
}

#[test]
fn 只读信封错误不透传上游原始消息() {
    let error = parse_envelope(r#"{"code":500,"msg":"secret raw upstream detail\nprivate"}"#)
        .expect_err("非成功信封必须返回稳定错误");

    assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
    assert_eq!(error.message, "阳光打卡请求失败");
    assert!(!error.message.contains("secret"));
    assert!(!error.message.contains('\n'));
}
