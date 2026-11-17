//! 健康云只读成绩页面投影。
use super::client::{
    BridgeClient, BridgeError, BridgeRouteDecision, catch_panic, disposed_error, map_route,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeHealthCloudYear {
    pub year: u16,
    pub key: String,
}

#[derive(Clone, Debug)]
pub struct BridgeHealthCloudEvent {
    pub name: String,
    pub result: Option<String>,
    pub score: Option<f64>,
    pub grade: Option<String>,
}

#[derive(Clone, Debug)]
pub struct BridgeHealthCloudReport {
    pub height_cm: Option<f64>,
    pub weight_kg: Option<f64>,
    pub lung_ml: Option<f64>,
    pub reach_cm: Option<f64>,
    pub events: Vec<BridgeHealthCloudEvent>,
}

impl From<core::HealthCloudReport> for BridgeHealthCloudReport {
    fn from(report: core::HealthCloudReport) -> Self {
        Self {
            height_cm: report.height_cm,
            weight_kg: report.weight_kg,
            lung_ml: report.lung_ml,
            reach_cm: report.reach_cm,
            events: report
                .events
                .into_iter()
                .map(|event| BridgeHealthCloudEvent {
                    name: event.name,
                    result: event.result,
                    score: event.score,
                    grade: event.grade,
                })
                .collect(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgeHealthCloudPage {
    pub years: Vec<BridgeHealthCloudYear>,
    pub selected_year: Option<String>,
    pub report: Option<BridgeHealthCloudReport>,
    pub route: BridgeRouteDecision,
}

impl BridgeClient {
    /// 读取某个年份或网站当前的体测页面。
    ///
    /// # Errors
    /// 会话未就绪或站点读取失败。
    #[allow(clippy::needless_pass_by_value)]
    pub async fn health_cloud_page(
        &self,
        year: Option<String>,
    ) -> Result<BridgeHealthCloudPage, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let result = client
                .health_cloud_page(year.as_deref())
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeHealthCloudPage {
                years: result
                    .data
                    .years
                    .into_iter()
                    .map(|year| BridgeHealthCloudYear {
                        year: year.year,
                        key: year.key,
                    })
                    .collect(),
                selected_year: result.data.selected_year,
                report: result.data.report.map(Into::into),
                route: map_route(result.resolution),
            })
        })
        .await
    }
}
