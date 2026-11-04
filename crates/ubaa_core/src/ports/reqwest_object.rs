use super::{ReqwestTransport, collect_response_body, transport_error};
use crate::error::{Result, UbaaError};
use crate::ports::{HttpFileRange, HttpMethod, HttpRequest, HttpResponse, HttpTransferObserver};
use std::{collections::BTreeMap, sync::Arc, time::Instant};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};

fn local() -> UbaaError {
    UbaaError::invalid_input("本机传输文件不可读写或内容已变化")
}
fn rejected() -> UbaaError {
    UbaaError::upstream_changed("对象传输未取得可接受的完整响应")
}
fn metadata(response: &reqwest::Response) -> HttpResponse {
    let mut headers = BTreeMap::<String, Vec<String>>::new();
    for (name, value) in response.headers() {
        if let Ok(value) = value.to_str() {
            headers
                .entry(name.as_str().into())
                .or_default()
                .push(value.into());
        }
    }
    HttpResponse {
        status: response.status().as_u16(),
        final_url: response.url().to_string(),
        headers,
        body: vec![],
    }
}
impl ReqwestTransport {
    pub(in crate::ports) async fn upload_object(
        &self,
        request: HttpRequest,
        source: Option<HttpFileRange>,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        observer.check()?;
        let method = match request.method {
            HttpMethod::Put => reqwest::Method::PUT,
            HttpMethod::Post => reqwest::Method::POST,
            _ => return Err(rejected()),
        };
        let mut builder = self.object_client.request(method, &request.url);
        for (name, value) in request.headers {
            if source.is_none() || !name.eq_ignore_ascii_case("content-length") {
                builder = builder.header(name, value);
            }
        }
        if let Some(source) = source {
            let mut file = tokio::fs::File::from_std(source.file);
            file.seek(std::io::SeekFrom::Start(source.offset))
                .await
                .map_err(|_| local())?;
            let length = source.length;
            let stream = futures_util::stream::try_unfold(
                (file, length, observer),
                |(mut file, remaining, observer)| async move {
                    observer.check()?;
                    if remaining == 0 {
                        return Ok::<_, UbaaError>(None);
                    }
                    let size = usize::try_from(remaining.min(64 * 1024)).map_err(|_| local())?;
                    let mut bytes = vec![0; size];
                    file.read_exact(&mut bytes).await.map_err(|_| local())?;
                    observer.check()?;
                    observer.advance(size as u64);
                    Ok(Some((bytes, (file, remaining - size as u64, observer))))
                },
            );
            builder = builder
                .header(reqwest::header::CONTENT_LENGTH, length)
                .body(reqwest::Body::wrap_stream(stream));
        } else {
            builder = builder.body(request.body);
        }
        let started = Instant::now();
        let mut response = builder
            .send()
            .await
            .map_err(|error| transport_error(&error))?;
        let mut result = metadata(&response);
        result.body = collect_response_body(&mut response, started).await?;
        Ok(result)
    }
    pub(in crate::ports) async fn download_object(
        &self,
        request: HttpRequest,
        destination: std::fs::File,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        observer.check()?;
        if request.method != HttpMethod::Get || !request.body.is_empty() {
            return Err(rejected());
        }
        let mut builder = self.object_client.get(&request.url);
        for (name, value) in request.headers {
            builder = builder.header(name, value);
        }
        let mut response = builder
            .send()
            .await
            .map_err(|error| transport_error(&error))?;
        let result = metadata(&response);
        if result.status != 200 || !crate::ports::same_url(&result.final_url, &request.url) {
            return Err(rejected());
        }
        let expected = response.content_length();
        if let Some(total) = expected {
            observer.set_total(total);
        }
        let mut file = tokio::fs::File::from_std(destination);
        let mut written = 0u64;
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|error| transport_error(&error))?
        {
            observer.check()?;
            for block in chunk.chunks(64 * 1024) {
                observer.check()?;
                file.write_all(block).await.map_err(|_| local())?;
                written = written
                    .checked_add(block.len() as u64)
                    .ok_or_else(rejected)?;
                observer.advance(block.len() as u64);
            }
        }
        observer.check()?;
        if expected.is_some_and(|length| length != written) {
            return Err(rejected());
        }
        file.sync_all().await.map_err(|_| local())?;
        Ok(result)
    }
}
