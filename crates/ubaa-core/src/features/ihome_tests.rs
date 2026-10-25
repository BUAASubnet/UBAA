use super::ihome::parser::{appeal, envelope, page};
use crate::domain::IhomeScope;
use serde_json::json;

#[test]
fn ihome_业务失败不能显示为空列表() {
    assert!(envelope(r#"{"code":40001,"success":"","data":[],"message":"私密正文"}"#).is_err());
    assert!(envelope(r#"{"code":20000,"success":true}"#).is_err());
}

#[test]
fn ihome_评价包装与当前轮次且丢弃个人字段() {
    let value = json!({"id":42,"content":"<p>测试诉求</p>","is_restart":1,"is_user":1,
        "is_follow":0,"user":{"phone":"隐私电话"},
        "change_history":[{"contents":"旧轮次","restart":0},{"contents":"本轮","restart":1}],
        "appeal_reply":[{"content":"官方答复","department":{"name":"服务中心"}}]});
    let result = appeal(&value).unwrap();
    assert_eq!(result.content, "测试诉求");
    assert_eq!(result.is_followed, Some(false));
    assert_eq!(result.is_supported, None);
    assert_eq!(result.history.len(), 1);
    assert_eq!(result.history[0].content, "本轮");
    assert!(!serde_json::to_string(&result).unwrap().contains("隐私电话"));
    let result = page(
        &json!({"current_page":1,"last_page":2,"total":3,
        "data":[{"id":9,"appeal":value,"speed":5}]}),
        IhomeScope::Appraised,
    )
    .unwrap();
    assert_eq!(result.entries[0].appeal.id, 42);
    assert_eq!(result.entries[0].evaluation.as_ref().unwrap().id, 9);
    assert!(page(&json!({}), IhomeScope::Public).is_err());
}
