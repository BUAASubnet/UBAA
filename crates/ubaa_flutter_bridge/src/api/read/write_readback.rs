//! 提交后的 caller-pinned 读取，复用原 DTO 映射，不重新解析路线。
use super::{
    BridgePinnedBykcChosen, BridgePinnedLibbookBookings, BridgePinnedSigninClasses,
    map_bykc_chosen_courses, map_libbook_bookings, map_signin_classes,
};
use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeError};

impl BridgeClient {
    pub async fn bykc_chosen_courses_on_route(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<BridgePinnedBykcChosen, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(async move { client.bykc_chosen_courses_on_route(route.into()).await })
                },
                map_bykc_chosen_courses,
            )
            .await?;
        Ok(BridgePinnedBykcChosen { data, pinned_route })
    }
    pub async fn libbook_bookings_on_route(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        limit: i32,
    ) -> Result<BridgePinnedLibbookBookings, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(async move {
                        client
                            .libbook_bookings_on_route(route.into(), page, limit)
                            .await
                    })
                },
                map_libbook_bookings,
            )
            .await?;
        Ok(BridgePinnedLibbookBookings { data, pinned_route })
    }
    pub async fn signin_today_on_route(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<BridgePinnedSigninClasses, BridgeError> {
        let (data, pinned_route) = self
            .execute_caller_pinned_read(
                move |client| {
                    Box::pin(async move { client.signin_today_on_route(route.into()).await })
                },
                map_signin_classes,
            )
            .await?;
        Ok(BridgePinnedSigninClasses { data, pinned_route })
    }
}
