#[path = "signin/write_authority.rs"]
mod write_authority;

#[test]
fn 允许目标在最终写前复核并只提交一次() {
    write_authority::allowed_target_is_rechecked_and_submitted_once_with_separated_identifiers();
}
