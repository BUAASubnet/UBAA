use ubaa_core::facade::{
    CampusAmount, CampusMetric, CampusMetrics, FinanceIncome, FinanceIncomes, NetworkProductUsage,
    NetworkUsage, PortalProfile,
};

pub(crate) fn campus_profile() -> PortalProfile {
    PortalProfile {
        identity: "本科生".into(),
        department: "示例学院".into(),
        fetched_at: 123,
    }
}

pub(crate) fn campus_metrics() -> CampusMetrics {
    CampusMetrics {
        network_balance: CampusMetric::Success {
            value: amount("12.34", ""),
            fetched_at: 123,
        },
        card_balance: CampusMetric::Success {
            value: amount("20.50", "元"),
            fetched_at: 124,
        },
        unread_mail: CampusMetric::Failure {
            error: ubaa_core::facade::UbaaError::upstream_unavailable("该校园指标暂时不可用"),
            fetched_at: 125,
        },
        borrowed_books: CampusMetric::Success {
            value: 0,
            fetched_at: 126,
        },
        cloud_storage_remaining: CampusMetric::Success {
            value: amount("80.125", "G"),
            fetched_at: 127,
        },
    }
}

fn amount(value: &str, unit: &str) -> CampusAmount {
    CampusAmount {
        value: value.into(),
        unit: unit.into(),
    }
}

pub(crate) fn campus_network() -> NetworkUsage {
    NetworkUsage {
        products: vec![NetworkProductUsage {
            product_name: "合成学生产品".into(),
            used: amount("90.001", "G"),
            free_remaining: amount("0", "byte"),
            billable_remaining: amount("40.125", "G"),
        }],
        remaining_excludes_packages: false,
        fetched_at: 128,
    }
}

pub(crate) fn finance_incomes() -> FinanceIncomes {
    let populated = FinanceIncome {
        id: "synthetic-income-present".into(),
        project: Some("合成发放项目".into()),
        description: None,
        department: Some("示例学院".into()),
        project_code: Some("SYNTH-PROJECT-01".into()),
        project_name: Some("合成项目名称".into()),
        amount_cents: Some(10000),
        tax_cents: Some(0),
        paid_cents: Some(10000),
        tax_rate: None,
        recorded_date: None,
        year: None,
        month: None,
    };
    let missing = FinanceIncome {
        id: "synthetic-income-missing".into(),
        department: None,
        project_code: None,
        project_name: None,
        ..populated.clone()
    };
    FinanceIncomes {
        entries: vec![populated, missing],
        total: 2,
    }
}
