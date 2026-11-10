use sha2::{Digest, Sha256};

use super::TelemetryUser;

#[test]
fn normalizes_confirmed_account_and_uses_contract_prefix() {
    let normalized = format!("AB{:02}{:06}", 24, 7);
    let raw = format!(" \t{}\n", normalized.to_lowercase());
    let identity = TelemetryUser::from_confirmed_username(&raw, 2026).unwrap();
    let expected = hex::encode(Sha256::digest(
        format!("ubaa-telemetry-user-v1:{normalized}").as_bytes(),
    ));
    assert!(identity.key() == expected);
    assert!(
        TelemetryUser::from_confirmed_username(&normalized, 2026)
            .is_some_and(|second| second == identity)
    );
    assert!(TelemetryUser::from_confirmed_username("  \t", 2026).is_none());
}

#[test]
fn cohort_follows_prefix_and_campus_year() {
    let cases = [
        (format!("{:02}{:06}", 24, 7), "undergrad", Some(2024)),
        (format!("{:02}", 0), "undergrad", Some(2000)),
        (format!(" cd{:02}{:04}", 27, 7), "CD", Some(2027)),
        (format!("cd{:02}{:04}", 28, 7), "unknown", None),
        (format!("{:02}{:06}", 28, 7), "unknown", None),
        (format!("{:02}x", 24), "unknown", None),
        (String::from("STAFF-EXAMPLE"), "unknown", None),
        (String::from("7"), "unknown", None),
    ];
    for (input, cohort_type, cohort_year) in cases {
        let user = TelemetryUser::from_confirmed_username(&input, 2026).unwrap();
        assert!(user.cohort_type == cohort_type);
        assert!(user.cohort_year == cohort_year);
    }
}
