use super::parse;

#[test]
fn 缺少目录数组不能被解释成空目录() {
    assert!(parse::directory(br#"{"files":[]}"#).is_err());
    assert!(parse::directory(br#"{"dirs":[]}"#).is_err());
    assert_eq!(
        parse::directory(br#"{"dirs":[],"files":[]}"#)
            .unwrap()
            .len(),
        0
    );
}

#[test]
fn 下载准备不泄露签名且不接受短授权与不安全地址() {
    let d=super::download::inspect(br#"{"authrequest":["GET","https://object.example.test/file?signature=private","Authorization: private"]}"#,false).unwrap();
    let safe = serde_json::to_string(&d).unwrap();
    assert!(!safe.contains("signature"));
    assert!(!safe.contains("private"));
    assert!(!d.destination_verified);
    for body in [
        br#"{"authrequest":["GET"]}"#.as_slice(),
        br#"{"authrequest":["GET","http://object.example.test/file"]}"#,
        br#"{"authrequest":["PUT","https://object.example.test/file"]}"#,
    ] {
        assert!(super::download::inspect(body, false).is_err());
    }
}
