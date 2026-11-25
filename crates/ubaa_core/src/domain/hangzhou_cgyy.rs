//! 杭州校区空间预约（hzsm）的预约与取消写入模型。
//!
//! 字段依据见 `docs/protocol/parity/cgyy.md` 杭州专项记录（2026-11-25 账号本人浏览器实录）。
//! 杭州与北京研讨室虽是同一厂商产品，但提交表单、确认与取消流程不同，因此单独建模。

use std::fmt;

use serde::{Deserialize, Serialize};

use super::CgyyReservationSelection;

/// 滑块验证码挑战：图片交给用户拖动，`secret_key` 只用于 Core 加密用户给出的位移。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyCaptchaChallenge {
    pub token: String,
    pub secret_key: String,
    /// 背景图（PNG Base64，不含 `data:` 前缀）。
    pub original_image_base64: String,
    /// 滑块拼图（PNG Base64，不含 `data:` 前缀）。
    pub jigsaw_image_base64: String,
}

impl fmt::Debug for HangzhouCgyyCaptchaChallenge {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HangzhouCgyyCaptchaChallenge")
            .field("token", &"[已隐藏]")
            .field("secret_key", &"[已隐藏]")
            .field(
                "original_image_base64_len",
                &self.original_image_base64.len(),
            )
            .field("jigsaw_image_base64_len", &self.jigsaw_image_base64.len())
            .finish()
    }
}

/// 用户亲手完成的滑块结果与提交按钮的真实点击坐标。
#[derive(Clone, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyUserInput {
    pub captcha_token: String,
    pub captcha_secret_key: String,
    /// 用户把拼图拖到的横向位置，按验证码原图像素（宽 310）计。
    pub slider_offset_x: f64,
    /// 用户点击“提交预约”时的窗口坐标；对应网页 `orderPin` 的 `clientX,clientY`。
    pub tap_x: i32,
    pub tap_y: i32,
}

impl fmt::Debug for HangzhouCgyyUserInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HangzhouCgyyUserInput")
            .field("captcha_token", &"[已隐藏]")
            .field("captcha_secret_key", &"[已隐藏]")
            .field("slider_offset_x", &self.slider_offset_x)
            .finish_non_exhaustive()
    }
}

/// 杭州空间预约提交请求。只支持免费场地；收费场地在发送任何写请求前拒绝。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyReservationRequest {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub selections: Vec<CgyyReservationSelection>,
    pub phone: String,
    #[serde(default, skip_serializing)]
    pub user_input: HangzhouCgyyUserInput,
}

/// 预约并完成 0 元确认后的安全收据。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyReservationReceipt {
    pub order_id: i64,
    pub trade_no: String,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
}

/// 杭州订单取消请求；`trade_no` 来自“我的预约”，原因原样提交给场馆系统。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyCancelRequest {
    pub trade_no: String,
    pub reason: String,
}

/// 取消前的提醒（网页 `cancel_tip`），为空表示没有提醒。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyCancelPreflight {
    pub trade_no: String,
    pub tip: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangzhouCgyyCancelResult {
    pub success: bool,
    pub message: String,
}
