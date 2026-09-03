use std::time::Duration;

use ubaa_core::facade::NetworkState;
use ubaa_core::facade::testing::GatewayProbe;

#[path = "judge/concurrency.rs"]
mod concurrency;
#[path = "judge/isolation.rs"]
mod isolation;
#[path = "judge/read.rs"]
mod read;
#[path = "judge/retry.rs"]
mod retry;

const JUDGE_LOGIN_URL: &str =
    "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F";

#[derive(Clone, Copy)]
struct UnknownGatewayProbe;

impl GatewayProbe for UnknownGatewayProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        NetworkState::Unknown
    }
}
