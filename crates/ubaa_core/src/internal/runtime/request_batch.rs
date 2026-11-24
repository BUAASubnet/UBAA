//! 同一运行时的只读小批次，所有请求完成后统一处理响应 Cookie。
use super::{ClientRuntime, ErrorCode, HttpRequest, HttpResponse, Result, SystemTime};
use crate::error::UbaaError;

impl ClientRuntime {
    pub(crate) async fn download_stream(
        &mut self,
        mut request: HttpRequest,
        destination: &std::path::Path,
        limit: u64,
        session_cookies: bool,
    ) -> Result<crate::ports::StreamDownload> {
        let mut sink = crate::ports::StreamSink::new(destination, limit)?;
        let now = self.now();
        if session_cookies {
            self.prepare_request_cookie(&mut request, now)?;
        }
        self.check_authentication_scope()?;
        self.ensure_session_revision()?;
        let url = request.url.clone();
        let permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        self.check_school_requests()?;
        let pending = self.transport.download_stream(request, &mut sink);
        drop(permit);
        let result = pending.await;
        let head = self.finish_request_response(result, &url, session_cookies.then_some(now))?;
        self.ensure_session_revision()?;
        let deliver = || {
            self.ensure_readonly_generation()?;
            self.check_operation_controls()?;
            sink.deliver(head)
        };
        if let Some(guard) = &self.shared_account {
            guard.with_current(deliver)?
        } else {
            deliver()
        }
    }
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
        cookie_time: Option<SystemTime>,
    ) -> Result<HttpResponse> {
        if let Err(error) = &result
            && matches!(error.code, ErrorCode::NetworkError | ErrorCode::Timeout)
            && let Some(domain) = request_domain(request_url)
        {
            self.network_failure_domain = Some(domain);
        }
        let response = result?;
        if let Some(scope) = &self.shared_account {
            scope.check()?;
        }
        if self.readonly_generation.is_some() {
            self.ensure_session_revision()?;
        }
        self.check_authentication_scope()?;
        let response = self.check_campus_network_page(response, request_url)?;
        if let Some(domain) = request_domain(request_url) {
            self.reached_domains.insert(domain);
        }
        if let Some(now) = cookie_time {
            self.jar.store_response(&response, request_url, now)?;
        }
        Ok(response)
    }

    pub(super) fn check_campus_network_page(
        &mut self,
        response: HttpResponse,
        request_url: &str,
    ) -> Result<HttpResponse> {
        if self.is_campus_network_page(&response) {
            self.network_failure_domain = request_domain(request_url);
            return Err(UbaaError::campus_network_required(response.status));
        }
        Ok(response)
    }

    pub(super) fn observe_campus_network_page(
        &mut self,
        response: &HttpResponse,
        request_url: &str,
    ) {
        if self.is_campus_network_page(response) {
            self.network_failure_domain = request_domain(request_url);
            self.campus_network_write_status = Some(response.status);
            if let Some(observer) = &self.campus_network_write_observer {
                observer.store(response.status, std::sync::atomic::Ordering::Release);
            }
        }
    }

    fn is_campus_network_page(&self, response: &HttpResponse) -> bool {
        self.mode() == crate::domain::ConnectionMode::Direct
            && (200..300).contains(&response.status)
            && response.body.len() <= 1024
            && std::str::from_utf8(&response.body).is_ok_and(|html| {
                html.trim_start().starts_with('<')
                    && html
                        .chars()
                        .filter(|c| !c.is_whitespace())
                        .collect::<String>()
                        .eq_ignore_ascii_case(
                            "<html><body><h1>请在校园网环境下访问</h1></body></html>",
                        )
            })
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
            .map(|(response, url)| self.finish_request_response(response, &url, Some(now)))
            .collect())
    }
}

fn request_domain(request_url: &str) -> Option<String> {
    crate::connection::from_webvpn_url(request_url)
        .ok()
        .and_then(|url| url::Url::parse(&url).ok())
        .and_then(|url| url.host_str().map(str::to_owned))
}
