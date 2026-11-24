use crate::{
    domain::{
        ReadonlyFeature, SpocCourse, SpocCourseFile, SpocDownloadReceipt, SpocDownloadTarget,
    },
    facade::{RoutedResult, UbaaClient, types::Operation},
    features::spoc::{course_files, files},
};
use std::path::Path;

impl UbaaClient {
    /// 读取当前学期的 SPOC 课程。
    /// # Errors
    /// 路线、认证或课程读取失败时返回错误。
    pub async fn spoc_courses(&mut self) -> RoutedResult<Vec<SpocCourse>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            course_files::courses(self.runtime_for(resolution.mode)).await
        );
        self.finish_routed(resolution, result)
    }
    /// 读完课程根目录或指定文件夹的全部课件页。
    /// # Errors
    /// 路线、认证、分页或目录标识无效时返回错误。
    pub async fn spoc_course_files(
        &mut self,
        course_id: &str,
        folder_id: Option<&str>,
    ) -> RoutedResult<Vec<SpocCourseFile>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            course_files::list(self.runtime_for(resolution.mode), course_id, folder_id).await
        );
        self.finish_routed(resolution, result)
    }
    /// 将附件、个人已提交文件或课件交付到宿主选择的路径。
    /// # Errors
    /// 认证、上游下载、大小检查或本机交付失败时返回错误。
    pub async fn spoc_download(
        &mut self,
        target: &SpocDownloadTarget,
        dest_path: &Path,
    ) -> RoutedResult<SpocDownloadReceipt> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(
            self,
            resolution,
            files::download(self.runtime_for(resolution.mode), target, dest_path).await
        );
        self.finish_routed(resolution, result)
    }
}
