//! Cgyy 验证码挑战、图像位移求解和校验流程。

use std::collections::BTreeMap;

use base64::Engine as _;
use serde_json::Value;

use crate::domain::CgyyReservationSubmitRequest;
use crate::error::Result;
use crate::ports::HttpMethod;
use crate::runtime::ClientRuntime;

use super::auth::{business_request, get};
use super::crypto::build_captcha_solution;
use super::parser::{data, error};
use super::sign::timestamp_millis;

/// 验证码挑战的脱敏结构；图像求解过程仅在 Core 内部流转。
#[allow(dead_code)]
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct CgyyCaptchaChallenge {
    pub(crate) secret_key: String,
    pub(crate) token: String,
    pub(crate) original_image_base64: String,
    pub(crate) jigsaw_image_base64: String,
}

impl std::fmt::Debug for CgyyCaptchaChallenge {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CgyyCaptchaChallenge")
            .field("secret_key", &"[已隐藏]")
            .field("token", &"[已隐藏]")
            .field(
                "original_image_base64_len",
                &self.original_image_base64.len(),
            )
            .field("jigsaw_image_base64_len", &self.jigsaw_image_base64.len())
            .finish()
    }
}

/// 使用冻结验证码密钥生成校验点和预约提交凭据。
///
/// 图像求解器只需提供滑块横向位移；密钥、令牌和 AES-ECB/PKCS#7 细节不会暴露给宿主。
/// 复刻冻结旧版的滑块位移匹配算法。输入为去除可选 data URI 前缀后的图片字节。
#[allow(dead_code)]
pub(crate) fn solve_captcha_offset(original: &[u8], jigsaw: &[u8]) -> Result<u32> {
    let background =
        image::load_from_memory(original).map_err(|_| error("验证码背景图无法解析"))?;
    let piece = image::load_from_memory(jigsaw).map_err(|_| error("验证码滑块图无法解析"))?;
    let bg = background.to_rgba8();
    let fg = piece.to_rgba8();
    let bg_gray = gray_pixels(&bg);
    let fg_gray = gray_pixels(&fg);
    let mask = build_image_mask(&fg);
    let (min_x, min_y, max_x, max_y) =
        image_bounds(&mask).ok_or_else(|| error("验证码图片缺少有效掩码"))?;
    let cropped_gray = crop_gray(&fg_gray, min_x, min_y, max_x, max_y);
    let cropped_mask = crop_mask(&mask, min_x, min_y, max_x, max_y);
    let bg_edges = edge_detect(&bg_gray);
    let piece_edges = edge_detect(&cropped_gray);
    let bg_h = bg_edges.len();
    let bg_w = bg_edges.first().map_or(0, Vec::len);
    let piece_h = piece_edges.len();
    let piece_w = piece_edges.first().map_or(0, Vec::len);
    if bg_h < piece_h || bg_w < piece_w {
        return Err(error("验证码图片尺寸无效"));
    }
    let mut best_score = f64::NEG_INFINITY;
    let mut best_x = 0u32;
    for y in 0..=(bg_h - piece_h) {
        for x in 0..=(bg_w - piece_w) {
            let mut score = 0.0;
            let mut edge_pixels = 0usize;
            let mut mask_pixels = 0usize;
            for py in 0..piece_h {
                for px in 0..piece_w {
                    if !cropped_mask[py][px] {
                        continue;
                    }
                    mask_pixels += 1;
                    let piece_value = piece_edges[py][px];
                    let bg_value = bg_edges[y + py][x + px];
                    if piece_value > 0 {
                        edge_pixels += 1;
                        score += if bg_value > 0 { 3.0 } else { -1.5 };
                    } else if bg_value == 0 {
                        score += 0.15;
                    }
                }
            }
            if mask_pixels == 0 || edge_pixels == 0 {
                continue;
            }
            score /= f64::from(u32::try_from(edge_pixels).unwrap_or(u32::MAX));
            score += f64::from(u32::try_from(mask_pixels).unwrap_or(u32::MAX)) * 0.0001;
            if score > best_score {
                best_score = score;
                best_x = u32::try_from(x).unwrap_or(u32::MAX);
            }
        }
    }
    Ok(best_x)
}

fn gray_pixels(image: &image::RgbaImage) -> Vec<Vec<i32>> {
    image
        .rows()
        .map(|row| {
            row.map(|pixel| {
                (i32::from(pixel[0]) * 30 + i32::from(pixel[1]) * 59 + i32::from(pixel[2]) * 11)
                    / 100
            })
            .collect()
        })
        .collect()
}

fn build_image_mask(image: &image::RgbaImage) -> Vec<Vec<bool>> {
    image
        .rows()
        .map(|row| {
            row.map(|pixel| {
                if pixel[3] > 10 {
                    true
                } else {
                    let luminance = (i32::from(pixel[0]) * 30
                        + i32::from(pixel[1]) * 59
                        + i32::from(pixel[2]) * 11)
                        / 100;
                    luminance < 250
                }
            })
            .collect()
        })
        .collect()
}

fn image_bounds(mask: &[Vec<bool>]) -> Option<(usize, usize, usize, usize)> {
    let mut bounds: Option<(usize, usize, usize, usize)> = None;
    for (y, row) in mask.iter().enumerate() {
        for (x, value) in row.iter().enumerate() {
            if !value {
                continue;
            }
            bounds = Some(match bounds {
                Some((min_x, min_y, max_x, max_y)) => {
                    (min_x.min(x), min_y.min(y), max_x.max(x), max_y.max(y))
                }
                None => (x, y, x, y),
            });
        }
    }
    bounds
}

fn crop_gray(
    source: &[Vec<i32>],
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
) -> Vec<Vec<i32>> {
    (min_y..=max_y)
        .map(|y| source[y][min_x..=max_x].to_vec())
        .collect()
}

fn crop_mask(
    source: &[Vec<bool>],
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
) -> Vec<Vec<bool>> {
    (min_y..=max_y)
        .map(|y| source[y][min_x..=max_x].to_vec())
        .collect()
}

fn edge_detect(gray: &[Vec<i32>]) -> Vec<Vec<u8>> {
    let height = gray.len();
    let width = gray.first().map_or(0, Vec::len);
    (0..height)
        .map(|y| {
            (0..width)
                .map(|x| {
                    let center = gray[y][x];
                    let right = gray[y][(x + 1).min(width.saturating_sub(1))];
                    let down = gray[(y + 1).min(height.saturating_sub(1))][x];
                    if (center - right).abs() + (center - down).abs() > 35 {
                        255
                    } else {
                        0
                    }
                })
                .collect()
        })
        .collect()
}

#[allow(dead_code)]
pub(super) fn build_captcha_params(now: i64) -> BTreeMap<String, String> {
    [
        ("captchaType".into(), "blockPuzzle".into()),
        ("clientUid".into(), format!("slider-{now}")),
        ("ts".into(), now.to_string()),
    ]
    .into_iter()
    .collect()
}

#[allow(dead_code)]
pub(super) fn parse_captcha_challenge(body: &str) -> Result<CgyyCaptchaChallenge> {
    let value = data(body)?;
    let success = value
        .get("success")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if !success {
        return Err(error(
            value
                .get("repMsg")
                .and_then(Value::as_str)
                .unwrap_or("获取验证码失败"),
        ));
    }
    let rep_data = value
        .get("repData")
        .and_then(Value::as_object)
        .ok_or_else(|| error("验证码数据缺失"))?;
    let required = |key: &str| {
        rep_data
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| error("验证码数据缺失"))
    };
    Ok(CgyyCaptchaChallenge {
        secret_key: required("secretKey")?,
        token: required("token")?,
        original_image_base64: required("originalImageBase64")?,
        jigsaw_image_base64: required("jigsawImageBase64")?,
    })
}

/// 构造冻结验证码校验表单。
#[must_use]
pub fn build_captcha_check_form(point_json: &str, token: &str) -> BTreeMap<String, String> {
    [
        ("pointJson".into(), point_json.into()),
        ("token".into(), token.into()),
    ]
    .into_iter()
    .collect()
}

pub(super) async fn prepare_captcha_once(
    runtime: &mut ClientRuntime,
    request: &mut CgyyReservationSubmitRequest,
) -> Result<()> {
    let challenge = if let (Some(secret_key), Some(original), Some(jigsaw)) = (
        request.captcha_secret_key.as_deref(),
        request.captcha_original_image_base64.as_deref(),
        request.captcha_jigsaw_image_base64.as_deref(),
    ) {
        CgyyCaptchaChallenge {
            secret_key: secret_key.to_owned(),
            token: request.captcha_token.clone(),
            original_image_base64: original.to_owned(),
            jigsaw_image_base64: jigsaw.to_owned(),
        }
    } else {
        get_captcha(runtime).await?
    };
    if challenge.token.is_empty() {
        return Err(error("验证码挑战令牌缺失"));
    }
    let original = decode_captcha_image(&challenge.original_image_base64)?;
    let jigsaw = decode_captcha_image(&challenge.jigsaw_image_base64)?;
    let offset = solve_captcha_offset(&original, &jigsaw)?;
    let (point_json, verification) =
        build_captcha_solution(&challenge.secret_key, &challenge.token, offset)?;
    request.captcha_point_json = point_json;
    request.captcha_token = challenge.token;
    request.captcha_verification = verification;
    check_captcha(runtime, request).await
}

async fn get_captcha(runtime: &mut ClientRuntime) -> Result<CgyyCaptchaChallenge> {
    let now = timestamp_millis()?;
    let body = get(runtime, "/api/captcha/get", build_captcha_params(now)).await?;
    parse_captcha_challenge(&body)
}

fn decode_captcha_image(value: &str) -> Result<Vec<u8>> {
    let encoded = value.split_once("base64,").map_or(value, |(_, data)| data);
    base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .map_err(|_| error("验证码图片编码无效"))
}

pub(super) async fn check_captcha(
    runtime: &mut ClientRuntime,
    request: &CgyyReservationSubmitRequest,
) -> Result<()> {
    let form = build_captcha_check_form(&request.captcha_point_json, &request.captcha_token);
    let body = business_request(runtime, HttpMethod::Post, "/api/captcha/check", form).await?;
    if data(&body)?.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(error("验证码校验失败"));
    }
    Ok(())
}
