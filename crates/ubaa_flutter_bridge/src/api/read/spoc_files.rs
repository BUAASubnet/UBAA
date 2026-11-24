use crate::api::{
    client::{BridgeClient, BridgeError, BridgeRouteDecision},
    read_pool::ReadGroup,
};
use ubaa_core::facade::SpocDownloadTarget;

#[derive(Debug, Clone)]
pub struct BridgeSpocSubmitAction {
    pub assignment_id: String,
    pub course_id: String,
    pub allowed_extensions: Vec<String>,
    pub max_submissions: Option<u32>,
    pub due_time: Option<String>,
    pub late_submission_deadline: Option<String>,
}
impl From<ubaa_core::facade::SpocSubmitAction> for BridgeSpocSubmitAction {
    fn from(value: ubaa_core::facade::SpocSubmitAction) -> Self {
        Self {
            assignment_id: value.assignment_id,
            course_id: value.course_id,
            allowed_extensions: value.allowed_extensions,
            max_submissions: value.max_submissions,
            due_time: value.due_time,
            late_submission_deadline: value.late_submission_deadline,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BridgeSpocAttachment {
    pub file_id: String,
    pub file_name: Option<String>,
    pub size_text: Option<String>,
    pub extension: Option<String>,
}
#[derive(Debug, Clone)]
pub struct BridgeSpocSubmittedFile {
    pub file_id: String,
    pub file_name: Option<String>,
}
#[derive(Debug, Clone)]
pub struct BridgeSpocCourse {
    pub course_id: String,
    pub name: String,
    pub teacher: Option<String>,
}
#[derive(Debug, Clone)]
pub struct BridgeSpocCourseFile {
    pub id: String,
    pub name: String,
    pub is_folder: bool,
    pub size_text: Option<String>,
    pub extension: Option<String>,
    pub uploaded_at_text: Option<String>,
    pub download_allowed: bool,
}
#[derive(Debug, Clone)]
pub struct BridgeSpocDownloadReceipt {
    pub file_name: String,
    pub byte_len: u64,
}
#[derive(Debug, Clone)]
pub struct BridgeRoutedSpocCourses {
    pub data: Vec<BridgeSpocCourse>,
    pub route: BridgeRouteDecision,
}
#[derive(Debug, Clone)]
pub struct BridgeRoutedSpocCourseFiles {
    pub data: Vec<BridgeSpocCourseFile>,
    pub route: BridgeRouteDecision,
}
#[derive(Debug, Clone)]
pub struct BridgeRoutedSpocDownload {
    pub data: BridgeSpocDownloadReceipt,
    pub route: BridgeRouteDecision,
}

impl BridgeClient {
    pub async fn spoc_courses(&self) -> Result<BridgeRoutedSpocCourses, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                |client| Box::pin(client.spoc_courses()),
                |courses| {
                    courses
                        .into_iter()
                        .map(|item| BridgeSpocCourse {
                            course_id: item.course_id,
                            name: item.name,
                            teacher: item.teacher,
                        })
                        .collect()
                },
            )
            .await?;
        Ok(BridgeRoutedSpocCourses { data, route })
    }
    pub async fn spoc_course_files(
        &self,
        course_id: String,
        folder_id: Option<String>,
    ) -> Result<BridgeRoutedSpocCourseFiles, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(async move {
                        client
                            .spoc_course_files(&course_id, folder_id.as_deref())
                            .await
                    })
                },
                |files| {
                    files
                        .into_iter()
                        .map(|item| BridgeSpocCourseFile {
                            id: item.id,
                            name: item.name,
                            is_folder: item.is_folder,
                            size_text: item.size_text,
                            extension: item.extension,
                            uploaded_at_text: item.uploaded_at_text,
                            download_allowed: item.download_allowed,
                        })
                        .collect()
                },
            )
            .await?;
        Ok(BridgeRoutedSpocCourseFiles { data, route })
    }
    pub async fn spoc_download_assignment_file(
        &self,
        file_id: String,
        file_name: Option<String>,
        dest_path: String,
    ) -> Result<BridgeRoutedSpocDownload, BridgeError> {
        self.download_spoc_target(
            SpocDownloadTarget::AssignmentFile { file_id, file_name },
            dest_path,
        )
        .await
    }
    pub async fn spoc_download_course_file(
        &self,
        id: String,
        name: String,
        dest_path: String,
    ) -> Result<BridgeRoutedSpocDownload, BridgeError> {
        self.download_spoc_target(SpocDownloadTarget::CourseFile { id, name }, dest_path)
            .await
    }
    async fn download_spoc_target(
        &self,
        target: SpocDownloadTarget,
        path: String,
    ) -> Result<BridgeRoutedSpocDownload, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(async move {
                        client
                            .spoc_download(&target, std::path::Path::new(&path))
                            .await
                    })
                },
                |item| BridgeSpocDownloadReceipt {
                    file_name: item.file_name,
                    byte_len: item.byte_len,
                },
            )
            .await?;
        Ok(BridgeRoutedSpocDownload { data, route })
    }
}
