//! 图片只从已证同路线 SSO 端点读取，解码前检查本地资源预算。

use std::io::Cursor;

use image::{ImageFormat, ImageReader, Limits};
use url::Url;

use crate::domain::CaptchaFrame;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

pub(super) async fn fetch_captcha_frame(
    runtime: &mut ClientRuntime,
    id: &str,
) -> Result<CaptchaFrame> {
    let mut url = Url::parse("https://sso.buaa.edu.cn/captcha").map_err(|_| invalid_image())?;
    url.query_pairs_mut().append_pair("captchaId", id);
    let target = runtime.url(url.as_str())?;
    let response = runtime.request(HttpRequest::get(&target)).await?;
    // 生产 transport 不自动跳转。本地边界只允许同路线的精确资源，未证跳转关闭。
    if response.status != 200 || response.final_url != target {
        return Err(invalid_image());
    }
    decode_captcha_frame(&response.body)
}

fn decode_captcha_frame(bytes: &[u8]) -> Result<CaptchaFrame> {
    if bytes.is_empty() || bytes.len() > 512 * 1024 {
        return Err(invalid_image());
    }
    let format = image::guess_format(bytes).map_err(|_| invalid_image())?;
    if !matches!(format, ImageFormat::Jpeg | ImageFormat::Png) {
        return Err(invalid_image());
    }
    let dimensions = ImageReader::with_format(Cursor::new(bytes), format)
        .into_dimensions()
        .map_err(|_| invalid_image())?;
    let (width, height) = dimensions;
    if width == 0
        || height == 0
        || width > 1024
        || height > 1024
        || u64::from(width) * u64::from(height) > 1_048_576
    {
        return Err(invalid_image());
    }
    let mut reader = ImageReader::with_format(Cursor::new(bytes), format);
    let mut limits = Limits::default();
    limits.max_image_width = Some(1024);
    limits.max_image_height = Some(1024);
    limits.max_alloc = Some(4 * 1024 * 1024);
    reader.limits(limits);
    let image = reader.decode().map_err(|_| invalid_image())?.into_rgba8();
    let rgba = image.into_raw();
    if rgba.len() > 4 * 1024 * 1024 {
        return Err(invalid_image());
    }
    Ok(CaptchaFrame {
        width,
        height,
        rgba,
    })
}

fn invalid_image() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "验证码图片暂不可用，请刷新后重试",
    )
}
