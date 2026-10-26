//! iHome 固定路线只读诊断入口。
#![allow(clippy::missing_errors_doc)]
use super::RouteClient;
use crate::domain::{FeatureResult, IhomeAppeal, IhomeConfig, IhomeNotice, IhomePage, IhomeQuery};
use crate::error::Result;
impl RouteClient {
    pub async fn ihome_page(&mut self, query: IhomeQuery) -> Result<FeatureResult<IhomePage>> {
        let data = crate::features::ihome::get_page(&mut self.runtime, &query).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn ihome_detail(
        &mut self,
        id: i64,
        mine: bool,
    ) -> Result<FeatureResult<IhomeAppeal>> {
        let data = crate::features::ihome::get_detail(&mut self.runtime, id, mine).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn ihome_config(&mut self) -> Result<FeatureResult<IhomeConfig>> {
        let data = crate::features::ihome::get_config(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn ihome_notices(&mut self) -> Result<FeatureResult<Vec<IhomeNotice>>> {
        let data = crate::features::ihome::get_notices(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn ihome_notice(&mut self, id: i64) -> Result<FeatureResult<IhomeNotice>> {
        let data = crate::features::ihome::get_notice(&mut self.runtime, id).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
