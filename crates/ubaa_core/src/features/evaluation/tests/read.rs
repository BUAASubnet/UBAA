use crate::ports::HttpResponse;

use super::super::read::ensure_activation_terminal;

#[test]
fn activation_terminal_rejects_a_path_that_only_shares_the_pjxt_prefix() {
    let response = HttpResponse::new(200, "https://spoc.buaa.edu.cn/pjxt-malicious", Vec::new());

    assert!(ensure_activation_terminal(&response).is_err());
}

#[test]
fn activation_terminal_accepts_only_the_pjxt_root_or_descendant() {
    for url in [
        "https://spoc.buaa.edu.cn/pjxt",
        "https://spoc.buaa.edu.cn/pjxt/",
        "https://spoc.buaa.edu.cn/pjxt/index",
    ] {
        assert!(ensure_activation_terminal(&HttpResponse::new(200, url, Vec::new())).is_ok());
    }
}
