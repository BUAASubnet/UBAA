//! 来源已证的图像验证码准备与一次性提交。

use std::collections::BTreeMap;

use crate::domain::{LoginInput, UserProfile};
use crate::error::{ErrorCode, Result};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;
use crate::upstream::interactive_auth::{ImageCaptchaPage, parse_image_captcha};
use crate::upstream::{SSO_LOGIN_URL, encode_form, extract_execution};

use super::{
    AuthWorkflow, activate_user_center, body_text, follow_login_response, is_redirect,
    status_error, upstream_changed,
};

pub(crate) enum InteractivePreparation {
    Plain,
    Image(ImageCaptchaPage),
    Ready(UserProfile),
}

pub(crate) enum InteractiveSubmission {
    Complete(UserProfile),
    Reprepared(InteractivePreparation),
}

impl AuthWorkflow {
    pub(crate) async fn prepare_interactive(
        &mut self,
        runtime: &mut ClientRuntime,
    ) -> Result<InteractivePreparation> {
        self.state.clear();
        let response = runtime
            .request(HttpRequest::get(runtime.url(SSO_LOGIN_URL)?))
            .await?;
        if is_redirect(response.status) {
            activate_user_center(runtime).await?;
            self.validate_status(runtime).await?;
            let profile = self.get_user_info(runtime).await?;
            return Ok(InteractivePreparation::Ready(
                self.finish_successful_login(runtime, profile),
            ));
        }
        if response.status != 200 {
            return Err(status_error(response.status, "SSO 登录页不可用"));
        }
        let page = body_text(&response);
        let captcha = parse_image_captcha(&page)?;
        let execution = extract_execution(&page)
            .ok_or_else(|| upstream_changed("SSO 登录页缺少 execution 令牌"))?;
        self.state.remember(page, execution);
        Ok(captcha.map_or(InteractivePreparation::Plain, InteractivePreparation::Image))
    }

    pub(crate) async fn submit_image_answer(
        &mut self,
        runtime: &mut ClientRuntime,
        input: LoginInput,
        expected: &ImageCaptchaPage,
        answer: &str,
        before_post: impl FnOnce() -> Result<()>,
    ) -> Result<InteractiveSubmission> {
        // 冻结旧版每次提交前先 GET；轮换时旧答案绝不进入 POST。
        let preparation = self.prepare_interactive(runtime).await?;
        let InteractivePreparation::Image(current) = preparation else {
            return Ok(InteractiveSubmission::Reprepared(preparation));
        };
        if current.id != expected.id || current.execution != expected.execution {
            return Ok(InteractiveSubmission::Reprepared(
                InteractivePreparation::Image(current),
            ));
        }
        before_post()?;
        let form = BTreeMap::from([
            ("username".into(), input.username),
            ("password".into(), input.password.expose_secret().to_owned()),
            ("captcha".into(), answer.to_owned()),
            ("captchaResponse".into(), answer.to_owned()),
            ("execution".into(), current.execution),
            ("_eventId".into(), "submit".into()),
            ("submit".into(), "登录".into()),
            ("type".into(), "username_password".into()),
        ]);
        let response = runtime
            .request(
                HttpRequest::post(runtime.url(SSO_LOGIN_URL)?, encode_form(&form))
                    .with_header("Content-Type", "application/x-www-form-urlencoded"),
            )
            .await?;
        follow_login_response(runtime, response)
            .await
            .map_err(|error| {
                if error.code == ErrorCode::InvalidCredentials {
                    // 冻结源未证实验证码失败与凭据失败可区分；不能因此删除保存密码。
                    upstream_changed("验证尚未完成，请刷新验证码后重试")
                } else {
                    error
                }
            })?;
        activate_user_center(runtime).await?;
        self.validate_status(runtime).await?;
        let profile = self.get_user_info(runtime).await?;
        Ok(InteractiveSubmission::Complete(
            self.finish_successful_login(runtime, profile),
        ))
    }
}
