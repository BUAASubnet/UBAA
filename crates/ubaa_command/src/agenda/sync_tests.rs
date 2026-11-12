use super::sync::AgendaSyncCommandResult;
use crate::{parse, runtime::CommandClass};
use ubaa_core::facade::{
    AgendaSyncError, AgendaSyncReport, AgendaSyncStatus, ErrorCode, ErrorKind, UbaaError,
};
#[test]
fn 同步命令只读与确认上传进入一次网络作业() {
    for args in [
        vec!["ubaa-cli", "agenda", "sync", "--pull"],
        vec!["ubaa-cli", "agenda", "sync", "--confirm-write"],
        vec!["ubaa-cli", "agenda", "sync", "--create", "--confirm-write"],
    ] {
        let plan = parse(args);
        assert!(plan.is_ok(), "同步命令必须可由 App 命令入口解析");
        let plan = plan.unwrap();
        assert_eq!(plan.requirements().class, CommandClass::SchoolWrite);
        assert!(plan.validate_local_arguments().is_ok());
    }
    assert!(
        parse(["ubaa-cli", "agenda", "sync"])
            .unwrap()
            .validate_local_arguments()
            .is_err()
    );
}

#[test]
fn 未验证及未知结果输出失败和待同步数量且匹配合同() {
    let schema: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../docs/contracts/cli-json.schema.json"
    )))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for (status, exit) in [
        (AgendaSyncStatus::UpToDate, 0),
        (AgendaSyncStatus::Pending, 0),
        (AgendaSyncStatus::Unverified, 6),
        (AgendaSyncStatus::OutcomeUnknown, 5),
        (AgendaSyncStatus::NeedsCreation, 2),
        (AgendaSyncStatus::Conflict, 6),
    ] {
        let (mut out, mut err) = (vec![], vec![]);
        let pending_count = if status == AgendaSyncStatus::UpToDate {
            0
        } else {
            2
        };
        assert_eq!(
            AgendaSyncCommandResult(Ok(AgendaSyncReport {
                status,
                pending_count,
                changed_count: 1
            }))
            .render(true, &crate::CommandControl::default(), &mut out, &mut err),
            exit
        );
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["ok"], exit == 0);
        if status == AgendaSyncStatus::Unverified {
            assert_eq!(value["error"]["code"], "sync_unverified");
        }
        assert_eq!(value["data"]["pendingCount"], pending_count);
        assert!(
            validator.is_valid(&value),
            "{:?}",
            validator
                .iter_errors(&value)
                .map(|e| e.to_string())
                .collect::<Vec<_>>()
        );
    }
}
#[test]
fn 网络认证与已发送未知保留机器码及退出码() {
    for (error, exit) in [
        (
            UbaaError::new(ErrorCode::Timeout, ErrorKind::Network, true, "合成超时"),
            5,
        ),
        (UbaaError::authentication_required("合成认证要求"), 3),
        (UbaaError::outcome_unknown("合成已发送结果未知"), 5),
    ] {
        let code = error.code;
        let control = crate::CommandControl::default();
        if code == ErrorCode::OutcomeUnknown {
            control.cancel();
        }
        let (mut out, mut err) = (vec![], vec![]);
        assert_eq!(
            AgendaSyncCommandResult(Err(AgendaSyncError::Remote(error)))
                .render(true, &control, &mut out, &mut err),
            exit
        );
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["error"]["code"], serde_json::to_value(code).unwrap());
    }
}

#[test]
fn 同步已确定总期限在取消通知后仍输出超时() {
    let control = crate::CommandControl::default();
    control.cancel();
    assert_eq!(control.check(), Err(crate::StopReason::Cancelled));
    let result = AgendaSyncCommandResult(Err(AgendaSyncError::Remote(UbaaError::new(
        ErrorCode::Timeout,
        ErrorKind::Network,
        false,
        "命令总期限已到达",
    ))));
    let (mut out, mut err) = (vec![], vec![]);
    let exit = result.render(true, &control, &mut out, &mut err);
    let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(
        (exit, value["error"]["code"].as_str()),
        (5, Some("timeout"))
    );
}
