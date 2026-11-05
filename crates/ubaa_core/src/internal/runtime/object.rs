use super::{
    Arc, AtomicBool, ClientRuntime, HttpRequest, HttpResponse, Ordering, Result, SessionStore,
    UbaaError, Weak, session_conflict, write_outcome_unknown,
};
use crate::domain::bhpan::transfer::BhpanTransfer;
use crate::ports::{HttpFileRange, HttpTransferObserver};

struct Observer {
    operation: Option<crate::facade::operation_control::OperationCheck>,
    transfer: BhpanTransfer,
    closed: Arc<AtomicBool>,
    shared: Option<crate::facade::SharedAccountGuard>,
    store: Arc<dyn SessionStore>,
    revision: u64,
}
impl HttpTransferObserver for Observer {
    fn check(&self) -> Result<()> {
        if let Some(check) = &self.operation {
            check()?;
        }
        self.transfer.ensure_active()?;
        if self.closed.load(Ordering::SeqCst) {
            return Err(UbaaError::client_closed());
        }
        if let Some(shared) = &self.shared {
            shared.check()?;
        }
        if !self.store.is_revision_current(self.revision)? {
            return Err(session_conflict());
        }
        if let Some(check) = &self.operation {
            check()?;
        }
        self.transfer.ensure_active()?;
        if self.closed.load(Ordering::SeqCst) {
            return Err(UbaaError::client_closed());
        }
        Ok(())
    }
    fn advance(&self, bytes: u64) {
        self.transfer.advance(bytes);
    }
    fn set_total(&self, bytes: u64) {
        self.transfer.set_total(bytes);
    }
}
impl ClientRuntime {
    fn object_observer(&self, transfer: &BhpanTransfer) -> Arc<dyn HttpTransferObserver> {
        Arc::new(Observer {
            operation: crate::facade::operation_control::current(),
            transfer: transfer.clone(),
            closed: self.consumer_closed.clone(),
            shared: self.shared_account.clone(),
            store: self.store.clone(),
            revision: self.session_revision,
        })
    }
    pub(crate) async fn object_upload<F>(
        &mut self,
        request: HttpRequest,
        body: Option<HttpFileRange>,
        transfer: &BhpanTransfer,
        pre_send: F,
    ) -> Result<HttpResponse>
    where
        F: FnOnce() -> Result<()>,
    {
        self.ensure_primary_client()?;
        self.ensure_session_revision()?;
        transfer.ensure_active()?;
        let observer = self.object_observer(transfer);
        let permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        self.check_operation_controls()?;
        transfer.ensure_active()?;
        pre_send()?;
        self.non_idempotent_boundary_crossed = true;
        if let Some(observer) = self.write_observer.as_ref().and_then(Weak::upgrade) {
            observer.store(true, Ordering::SeqCst);
        }
        let expected = body.as_ref().map(|range| range.length);
        let before = transfer.progress().bytes;
        let pending = self.transport.upload(request, body, observer);
        drop(permit);
        let result = tokio::select! {biased;_ = transfer.cancelled()=>return Err(write_outcome_unknown()),response=pending=>response};
        let response = result.map_err(|_| write_outcome_unknown())?;
        if expected
            .is_some_and(|length| transfer.progress().bytes.checked_sub(before) != Some(length))
        {
            return Err(write_outcome_unknown());
        }
        if let Some(shared) = &self.shared_account {
            shared.check().map_err(|_| write_outcome_unknown())?;
        }
        if !self
            .store
            .is_revision_current(self.session_revision)
            .map_err(|_| write_outcome_unknown())?
        {
            return Err(write_outcome_unknown());
        }
        Ok(response)
    }
    pub(crate) async fn object_download(
        &mut self,
        request: HttpRequest,
        file: std::fs::File,
        transfer: &BhpanTransfer,
    ) -> Result<HttpResponse> {
        self.ensure_primary_client()?;
        self.ensure_session_revision()?;
        transfer.ensure_active()?;
        let observer = self.object_observer(transfer);
        let permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        self.check_operation_controls()?;
        transfer.ensure_active()?;
        let pending = self.transport.download(request, file, observer);
        drop(permit);
        let response = tokio::select! {biased;error = transfer.cancelled()=>return Err(error),response=pending=>response}?;
        self.ensure_session_revision()?;
        transfer.ensure_active()?;
        Ok(response)
    }
}

#[cfg(test)]
#[path = "object_tests.rs"]
mod tests;
