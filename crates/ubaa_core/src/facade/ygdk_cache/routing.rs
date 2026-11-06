//! 切换路线时重新取得阳光打卡的分类和凭据。
use super::UbaaClient;
use crate::connection::RouteResolution;
use crate::domain::YgdkRecordsPage;
use crate::error::{Result, UbaaError};
use crate::features::ygdk::{self, YgdkOverviewContext};

impl UbaaClient {
    pub(super) async fn ygdk_records_context(
        &mut self,
        resolution: crate::connection::RouteResolution,
        pinned: bool,
    ) -> (
        crate::connection::RouteResolution,
        crate::error::Result<crate::features::ygdk::YgdkOverviewContext>,
    ) {
        if pinned {
            (
                resolution,
                ygdk::get_overview_context(self.runtime_for(resolution.mode)).await,
            )
        } else {
            crate::facade::routing::read_with_fallback!(
                self,
                resolution,
                ygdk::get_overview_context(self.runtime_for(resolution.mode)).await
            )
        }
    }
    pub(super) async fn ygdk_records_page(
        &mut self,
        resolution: RouteResolution,
        context: &YgdkOverviewContext,
        page: i32,
        size: i32,
        pinned: bool,
    ) -> (RouteResolution, Result<(YgdkRecordsPage, bool)>) {
        if pinned {
            return (
                resolution,
                ygdk::get_records_in_context(
                    self.runtime_for(resolution.mode),
                    context,
                    page,
                    size,
                )
                .await,
            );
        }
        let initial_route = resolution.mode;
        crate::facade::routing::read_with_fallback!(self, resolution, {
            let runtime = self.runtime_for(resolution.mode);
            if resolution.mode == initial_route {
                ygdk::get_records_in_context(runtime, context, page, size).await
            } else {
                match ygdk::get_overview_context(runtime).await {
                    Ok(next) if next.overview.classify_id == context.overview.classify_id => {
                        ygdk::get_records_in_context(runtime, &next, page, size).await
                    }
                    Ok(_) => Err(UbaaError::upstream_changed(
                        "阳光打卡分类已变化，请刷新概览",
                    )),
                    Err(error) => Err(error),
                }
            }
        })
    }
}
