use crate::{
    domain::{
        ReadonlyFeature,
        spoc_classroom::{
            ClassSummary, ClassroomCatalog, ClassroomSession, SlideTimeline, Transcript,
        },
    },
    facade::{RoutedResult, UbaaClient, types::Operation},
    features::msa,
};

impl UbaaClient {
    /// 按 SPOC 课程标识读取整学期的课堂节次。
    /// # Errors
    /// 身份不受支持、课程未开通、认证或上游协议异常时返回错误。
    pub async fn spoc_classroom_catalog(&mut self, kcid: &str) -> RoutedResult<ClassroomCatalog> {
        let resolution =
            self.resolve_operation(Operation::Feature(ReadonlyFeature::SpocClassroom))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            msa::catalog(self.runtime_for(resolution.mode), kcid).await
        );
        self.finish_routed(resolution, result)
    }
    /// 读取一节课的回放或直播源。
    /// # Errors
    /// 标识、认证、媒体主机或上游响应无效时返回错误。
    pub async fn spoc_classroom_session(
        &mut self,
        course_id: &str,
        sub_id: &str,
    ) -> RoutedResult<ClassroomSession> {
        let resolution =
            self.resolve_operation(Operation::Feature(ReadonlyFeature::SpocClassroom))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            msa::session(self.runtime_for(resolution.mode), course_id, sub_id).await
        );
        self.finish_routed(resolution, result)
    }
    /// 读取学校提供的逐字稿及毫秒时间轴。
    /// # Errors
    /// 标识、认证或上游响应无效时返回错误。
    pub async fn spoc_classroom_transcript(
        &mut self,
        sub_id: &str,
        resource_guid: &str,
    ) -> RoutedResult<Transcript> {
        let resolution =
            self.resolve_operation(Operation::Feature(ReadonlyFeature::SpocClassroom))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            msa::transcript(self.runtime_for(resolution.mode), sub_id, resource_guid).await
        );
        self.finish_routed(resolution, result)
    }
    /// 读取课堂总结、关键词、问答和章节。
    /// # Errors
    /// 标识、认证或上游响应无效时返回错误。
    pub async fn spoc_classroom_summary(
        &mut self,
        sub_id: &str,
        resource_guid: &str,
    ) -> RoutedResult<ClassSummary> {
        let resolution =
            self.resolve_operation(Operation::Feature(ReadonlyFeature::SpocClassroom))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            msa::summary(self.runtime_for(resolution.mode), sub_id, resource_guid).await
        );
        self.finish_routed(resolution, result)
    }
    /// 读取单节课的幻灯片截图时间轴。
    /// # Errors
    /// 标识、认证、图片主机或上游响应无效时返回错误。
    pub async fn spoc_classroom_slides(
        &mut self,
        course_id: &str,
        sub_id: &str,
        resource_guid: &str,
    ) -> RoutedResult<SlideTimeline> {
        let resolution =
            self.resolve_operation(Operation::Feature(ReadonlyFeature::SpocClassroom))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            msa::slides(
                self.runtime_for(resolution.mode),
                course_id,
                sub_id,
                resource_guid,
            )
            .await
        );
        self.finish_routed(resolution, result)
    }
}
