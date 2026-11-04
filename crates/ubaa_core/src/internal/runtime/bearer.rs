use super::{
    ClientRuntime, HttpRequest, HttpResponse, Ordering, Result, Weak, write_outcome_unknown,
};

impl ClientRuntime {
    /// 显式 Bearer API 使用独立 Cookie 边界，不接收或发送浏览器导航 Cookie。
    pub(crate) async fn request_bearer_only(
        &mut self,
        request: HttpRequest,
        write: bool,
    ) -> Result<HttpResponse> {
        self.request_bearer_only_checked(request, write, |_| Ok(()))
            .await
    }
    pub(crate) async fn request_bearer_only_checked<F>(
        &mut self,
        request: HttpRequest,
        write: bool,
        pre_send: F,
    ) -> Result<HttpResponse>
    where
        F: Fn(&Self) -> Result<()>,
    {
        if write {
            self.ensure_primary_client()?;
        }
        self.ensure_session_revision()?;
        self.check_authentication_scope()?;
        pre_send(self)?;
        let permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        self.check_operation_controls()?;
        pre_send(self)?;
        if write {
            self.non_idempotent_boundary_crossed = true;
            if let Some(observer) = self.write_observer.as_ref().and_then(Weak::upgrade) {
                observer.store(true, Ordering::SeqCst);
            }
        }
        let pending = self.transport.execute(request);
        drop(permit);
        let result = pending.await;
        if write {
            let response = result.map_err(|_| write_outcome_unknown())?;
            // 已收到确定响应后，普通关闭不改写结果；账号撤销与会话替换仍使结果待核对。
            if let Some(scope) = &self.shared_account {
                scope.check().map_err(|_| write_outcome_unknown())?;
            }
            if !self
                .store
                .is_revision_current(self.session_revision)
                .map_err(|_| write_outcome_unknown())?
            {
                return Err(write_outcome_unknown());
            }
            Ok(response)
        } else {
            let response = result?;
            self.ensure_session_revision()?;
            self.check_authentication_scope()?;
            Ok(response)
        }
    }
}
