use crate::domain::{
    ReadonlyFeature, SpocSubmitAction, SpocSubmitReceipt, bhpan::transfer::BhpanTransfer,
};
use crate::facade::{RoutedResult, SpocPreparedSubmission, UbaaClient};
use crate::features::spoc::submit;
use std::path::Path;

impl UbaaClient {
    /// 重新读取作业资格并将确认摘要绑定到所选文件。
    /// # Errors
    /// 路线、作业资格或文件不符合要求时返回错误。
    pub async fn prepare_spoc_submit_assignment(
        &mut self,
        action: &SpocSubmitAction,
        path: &Path,
        transfer: BhpanTransfer,
    ) -> RoutedResult<SpocPreparedSubmission> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Spoc, None)?;
        let result =
            submit::prepare(self.runtime_for(resolution.mode), action, path, transfer).await;
        self.finish_routed(resolution, result)
    }

    /// 消费预检结果，在确认路线提交一次并只读回查。
    /// # Errors
    /// 文件变化、上传失败、业务拒绝或提交结果未知时返回错误。
    pub async fn confirm_spoc_submit_assignment(
        &mut self,
        prepared: SpocPreparedSubmission,
    ) -> RoutedResult<SpocSubmitReceipt> {
        let resolution = self.resolve_write_route(ReadonlyFeature::Spoc, Some(prepared.route()))?;
        let runtime = self.runtime_for(resolution.mode);
        runtime.begin_non_idempotent_operation();
        let result = submit::confirm(runtime, prepared).await;
        self.finish_routed_write(resolution, result)
    }
}
