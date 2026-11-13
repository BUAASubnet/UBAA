//! 同一运行时的只读小批次，所有请求完成后统一处理响应 Cookie。
use super::{ClientRuntime, ErrorCode, HttpRequest, HttpResponse, Result, SystemTime};

impl ClientRuntime {
    pub(super) fn prepare_request_cookie(
        &mut self,
        request: &mut HttpRequest,
        now: SystemTime,
    ) -> Result<()> {
        let cookie = self.jar.cookie_header(&request.url, now)?;
        if !cookie.is_empty() {
            request.headers.insert("Cookie".into(), cookie);
        }
        Ok(())
    }

    pub(super) fn send_prepared_request(
        &self,
        request: HttpRequest,
    ) -> Result<futures_util::future::BoxFuture<'_, Result<HttpResponse>>> {
        self.check_authentication_scope()?;
        if self.readonly_generation.is_some() {
            self.ensure_session_revision()?;
        }
        let permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        self.check_school_requests()?;
        let pending = if crate::facade::operation_control::fast_connect() {
            self.transport.execute_with_fast_connect(request)
        } else {
            self.transport.execute(request)
        };
        drop(permit);
        Ok(pending)
    }

    pub(super) fn finish_request_response(
        &mut self,
        result: Result<HttpResponse>,
        request_url: &str,
        now: SystemTime,
    ) -> Result<HttpResponse> {
        let domain = crate::connection::from_webvpn_url(request_url)
            .ok()
            .and_then(|url| url::Url::parse(&url).ok())
            .and_then(|url| url.host_str().map(str::to_owned));
        match (&result, domain) {
            (Err(error), Some(domain))
                if matches!(error.code, ErrorCode::NetworkError | ErrorCode::Timeout) =>
            {
                self.network_failure_domain = Some(domain);
            }
            (Ok(_), Some(domain)) => {
                self.reached_domains.insert(domain);
            }
            _ => {}
        }
        let response = result?;
        if let Some(scope) = &self.shared_account {
            scope.check()?;
        }
        if self.readonly_generation.is_some() {
            self.ensure_session_revision()?;
        }
        self.check_authentication_scope()?;
        self.jar.store_response(&response, request_url, now)?;
        Ok(response)
    }

    /// 仅供已选定课程的详情 GET 使用；返回前没有在途请求。
    pub(crate) async fn request_judge_details(
        &mut self,
        mut requests: Vec<HttpRequest>,
    ) -> Result<Vec<Result<HttpResponse>>> {
        let now = self.now();
        for request in &mut requests {
            self.prepare_request_cookie(request, now)?;
        }
        let urls: Vec<_> = requests.iter().map(|r| r.url.clone()).collect();
        let responses = futures_util::future::join_all(
            requests
                .into_iter()
                .map(|request| self.send_prepared_request(request))
                .map(|pending| async move {
                    match pending {
                        Ok(future) => future.await,
                        Err(error) => Err(error),
                    }
                }),
        )
        .await;
        Ok(responses
            .into_iter()
            .zip(urls)
            .map(|(response, url)| self.finish_request_response(response, &url, now))
            .collect())
    }
}
