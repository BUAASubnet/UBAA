use serde_json::{Value, to_value};
use ubaa_command::{CliFeature, bhpan::BhpanOutput};
use ubaa_core::facade::{
    EvaluationCourse, IhomeAppeal, IhomeCategory, IhomeConfig, IhomeEntry, IhomeEvaluation,
    IhomeHistory, IhomeNotice, IhomePage, IhomeReply, SigninClass,
};

use crate::common::{campus_metrics, campus_network, campus_profile, finance_incomes};

pub(super) fn routed_service_success_representatives() -> Vec<(CliFeature, Value)> {
    let mut samples = vec![
        (CliFeature::Portal, to_value(campus_profile()).unwrap()),
        (CliFeature::Portal, to_value(campus_metrics()).unwrap()),
        (CliFeature::Network, to_value(campus_network()).unwrap()),
        (CliFeature::Finance, to_value(finance_incomes()).unwrap()),
        (CliFeature::Bhpan, to_value(BhpanOutput::Login).unwrap()),
        (
            CliFeature::Signin,
            to_value(Vec::<SigninClass>::new()).unwrap(),
        ),
        (CliFeature::LibBook, serde_json::json!([])),
        (
            CliFeature::Evaluation,
            to_value(Vec::<EvaluationCourse>::new()).unwrap(),
        ),
        (
            CliFeature::Ygdk,
            serde_json::json!({
                "success": true, "message": "阳光打卡已提交", "recordId": 77
            }),
        ),
    ];
    samples.extend(
        ihome_samples()
            .into_iter()
            .map(|data| (CliFeature::Ihome, data)),
    );
    samples
}

fn ihome_samples() -> [Value; 5] {
    let evaluation = IhomeEvaluation {
        id: 1,
        department: "示例部门".into(),
        speed: 5,
        satisfaction: 5,
        degree: 5,
        content: "示例评价".into(),
        created_at: "2025-09-01".into(),
    };
    let appeal = IhomeAppeal {
        id: 1,
        content: "示例诉求".into(),
        status: "已回复".into(),
        category: "示例类别".into(),
        published_at: "2025-09-01".into(),
        departments: vec!["示例部门".into()],
        is_mine: true,
        is_followed: None,
        is_supported: Some(false),
        follow_count: Some(0),
        support_count: None,
        replies: vec![IhomeReply {
            content: "示例回复".into(),
            department: "示例部门".into(),
            created_at: "2025-09-01".into(),
        }],
        evaluations: vec![evaluation.clone()],
        history: vec![IhomeHistory {
            content: "示例进度".into(),
            created_at: "2025-09-01".into(),
        }],
    };
    let notice = IhomeNotice {
        id: 1,
        title: "示例公告".into(),
        content: "示例内容".into(),
        date: "2025-09-01".into(),
    };
    [
        to_value(IhomePage {
            entries: vec![IhomeEntry {
                appeal: appeal.clone(),
                evaluation: Some(evaluation),
            }],
            page: 1,
            last_page: 1,
            total: 1,
        })
        .unwrap(),
        to_value(appeal).unwrap(),
        to_value(IhomeConfig {
            support_enabled: true,
            support_label: "支持".into(),
            categories: vec![IhomeCategory {
                id: 1,
                name: "示例类别".into(),
            }],
        })
        .unwrap(),
        to_value(vec![notice.clone()]).unwrap(),
        to_value(notice).unwrap(),
    ]
}
