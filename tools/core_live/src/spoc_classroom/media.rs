use std::{io, time::Duration};

use futures_util::{AsyncReadExt as _, TryStreamExt as _};
use reqwest::{Client, RequestBuilder, StatusCode, Url, header, redirect};

const PLAYLIST_MARKER: &[u8; 7] = b"#EXTM3U";

#[derive(Clone, Copy)]
pub(super) enum Probe {
    Http { status: u16, matches: bool },
    BodyError { status: u16 },
    RequestError(&'static str),
}

pub(crate) struct MediaReport {
    pub(super) proxy_env: bool,
    pub(super) replay: Option<Probe>,
    pub(super) live: Option<Probe>,
}

impl MediaReport {
    pub(super) fn fields(&self) -> Vec<(&'static str, String)> {
        let mut fields = vec![("http_proxy_env", self.proxy_env.to_string())];
        for (probe, status_key, matches_key, error_key) in [
            (
                self.replay,
                "replay_http_status",
                "replay_is_partial",
                "replay_probe_error",
            ),
            (
                self.live,
                "live_http_status",
                "live_starts_extm3u",
                "live_probe_error",
            ),
        ] {
            match probe {
                Some(Probe::Http { status, matches }) => {
                    fields.push((status_key, status.to_string()));
                    fields.push((matches_key, matches.to_string()));
                }
                Some(Probe::BodyError { status }) => {
                    fields.push((status_key, status.to_string()));
                    fields.push((error_key, "body_read_failed".into()));
                }
                Some(Probe::RequestError(code)) => fields.push((error_key, code.into())),
                None => {}
            }
        }
        fields
    }
}

pub(super) fn is_mp4(source: &str) -> bool {
    Url::parse(source).is_ok_and(|url| {
        url.path()
            .rsplit_once('.')
            .is_some_and(|(_, extension)| extension.eq_ignore_ascii_case("mp4"))
    })
}

pub(super) async fn probe(replay: Option<&str>, live: Option<&str>) -> MediaReport {
    let proxy_env = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"]
        .into_iter()
        .any(|key| std::env::var_os(key).is_some_and(|value| !value.is_empty()));
    let client = Client::builder()
        .redirect(redirect::Policy::none())
        .referer(false)
        .no_gzip()
        .no_brotli()
        .no_deflate()
        .no_zstd()
        .timeout(Duration::from_secs(10))
        .build();
    let replay = match replay {
        Some(source) => Some(probe_one(&client, source, true).await),
        None => None,
    };
    let live = match live {
        Some(source) => Some(probe_one(&client, source, false).await),
        None => None,
    };
    MediaReport {
        proxy_env,
        replay,
        live,
    }
}

fn request(client: &Client, source: &str, replay: bool) -> Result<RequestBuilder, &'static str> {
    let mut url = Url::parse(source).map_err(|_| "invalid_media_url")?;
    url.set_query(None);
    url.set_fragment(None);
    let builder = client.get(url);
    Ok(if replay {
        builder.header(header::RANGE, "bytes=0-1")
    } else {
        builder
    })
}

async fn probe_one(client: &reqwest::Result<Client>, source: &str, replay: bool) -> Probe {
    let Ok(client) = client else {
        return Probe::RequestError("client_init_failed");
    };
    let request = match request(client, source, replay) {
        Ok(request) => request,
        Err(code) => return Probe::RequestError(code),
    };
    let response = match request.send().await {
        Ok(response) => response,
        Err(error) => {
            return Probe::RequestError(if error.is_timeout() {
                "timeout"
            } else {
                "network_error"
            });
        }
    };
    let status = response.status().as_u16();
    if replay {
        return Probe::Http {
            status,
            matches: response.status() == StatusCode::PARTIAL_CONTENT,
        };
    }
    let mut prefix = [0; PLAYLIST_MARKER.len()];
    let mut body = response
        .bytes_stream()
        .map_err(io::Error::other)
        .into_async_read();
    match body.read_exact(&mut prefix).await {
        Ok(()) => Probe::Http {
            status,
            matches: &prefix == PLAYLIST_MARKER,
        },
        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => Probe::Http {
            status,
            matches: false,
        },
        Err(_) => Probe::BodyError { status },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn 媒体探测无需读取完整正文() {
        use std::{
            io::{BufRead as _, BufReader, Write as _},
            net::TcpListener,
            sync::mpsc,
        };

        let client = Client::builder()
            .no_proxy()
            .timeout(Duration::from_secs(3))
            .build();
        for (replay, response, expected_status, expected_match) in [
            (
                true,
                "206 Partial Content\r\nContent-Length: 2\r\n\r\n",
                206,
                true,
            ),
            (
                false,
                "200 OK\r\nContent-Length: 4096\r\n\r\n#EXTM3U",
                200,
                true,
            ),
            (
                false,
                "403 Forbidden\r\nContent-Length: 0\r\n\r\n",
                403,
                false,
            ),
        ] {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let source = format!("http://{}/sample", listener.local_addr().unwrap());
            let (release, released) = mpsc::channel::<()>();
            let server = std::thread::spawn(move || {
                let (mut stream, _) = listener.accept().unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(3)))
                    .unwrap();
                let mut reader = BufReader::new(&mut stream);
                let mut line = String::new();
                while reader.read_line(&mut line).unwrap() > 0 && line != "\r\n" {
                    line.clear();
                }
                write!(stream, "HTTP/1.1 {response}").unwrap();
                let _ = released.recv_timeout(Duration::from_secs(5));
            });
            let observed = probe_one(&client, &source, replay).await;
            drop(release);
            server.join().unwrap();
            assert!(
                matches!(observed, Probe::Http { status, matches } if status == expected_status && matches == expected_match)
            );
        }
    }

    #[tokio::test]
    async fn 媒体探测保留原站路径但不携带凭据或来源页() {
        let client = Client::new();
        for (replay, suffix) in [(true, "sample.mp4"), (false, "sample.m3u8")] {
            let source = format!("https://fixture.invalid/stream/{suffix}?auth_key=fixture-secret");
            let request = request(&client, &source, replay).unwrap().build().unwrap();
            assert_eq!(request.method(), reqwest::Method::GET);
            assert_eq!(
                request.url().as_str(),
                format!("https://fixture.invalid/stream/{suffix}")
            );
            for key in [header::AUTHORIZATION, header::COOKIE, header::REFERER] {
                assert!(!request.headers().contains_key(key));
            }
            assert_eq!(
                request
                    .headers()
                    .get(header::RANGE)
                    .map(|value| value.to_str().unwrap()),
                replay.then_some("bytes=0-1")
            );
        }
    }
}
