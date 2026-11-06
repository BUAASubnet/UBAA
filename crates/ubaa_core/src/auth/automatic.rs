//! 同一路线的限次静默验证码登录及人工输入交接。

use std::time::Instant;

use crate::domain::{CaptchaFrame, LoginInput, UserProfile};
use crate::error::{Result, UbaaError};
use crate::runtime::ClientRuntime;
use crate::upstream::interactive_auth::ImageCaptchaPage;

use super::AuthWorkflow;
use super::captcha_image::fetch_captcha_frame;
use super::interactive::{InteractivePreparation, InteractiveSubmission};

const MAX_AUTOMATIC_ATTEMPTS: usize = 3;

pub(crate) struct PendingManualCaptcha {
    pub(crate) username: String,
    pub(crate) page: ImageCaptchaPage,
    pub(crate) frame: CaptchaFrame,
    pub(crate) created_at: Instant,
}

impl AuthWorkflow {
    pub(crate) async fn login_automatically(
        &mut self,
        runtime: &mut ClientRuntime,
        input: LoginInput,
    ) -> Result<UserProfile> {
        runtime.ensure_primary_client()?;
        runtime.check_authentication_scope()?;
        if input.username.trim().is_empty() || input.password.expose_secret().is_empty() {
            return Err(UbaaError::invalid_input("用户名和密码不能为空"));
        }
        self.manual_captcha = None;
        let mut preparation = self.prepare_interactive(runtime).await?;
        for _ in 0..MAX_AUTOMATIC_ATTEMPTS {
            runtime.check_authentication_scope()?;
            let page = match preparation {
                InteractivePreparation::Plain => return self.login(runtime, input).await,
                InteractivePreparation::Ready(profile) => return Ok(profile),
                InteractivePreparation::Image(page) => page,
            };
            let frame = fetch_captcha_frame(runtime, &page.id).await?;
            let answer = self.recognize_captcha(frame).await;
            runtime.check_authentication_scope()?;
            let Some(answer) = answer else {
                preparation = self.prepare_interactive(runtime).await?;
                continue;
            };
            let submission = self
                .submit_image_answer(runtime, input.clone(), &page, &answer, || Ok(()))
                .await?;
            match submission {
                InteractiveSubmission::Complete(profile) => return Ok(profile),
                InteractiveSubmission::Rejected(next) => {
                    preparation = InteractivePreparation::Image(next);
                }
            }
        }
        match preparation {
            InteractivePreparation::Ready(profile) => Ok(profile),
            InteractivePreparation::Plain => Err(UbaaError::authentication_required(
                "登录页面已变化，请重新登录",
            )),
            InteractivePreparation::Image(page) => {
                let frame = fetch_captcha_frame(runtime, &page.id).await?;
                runtime.check_authentication_scope()?;
                self.manual_captcha = Some(PendingManualCaptcha {
                    username: input.username.trim().to_owned(),
                    page,
                    frame,
                    created_at: Instant::now(),
                });
                Err(UbaaError::captcha_required())
            }
        }
    }

    async fn recognize_captcha(&self, frame: CaptchaFrame) -> Option<String> {
        #[cfg(feature = "test-contract")]
        if let Some(recognize) = &self.captcha_recognizer {
            return recognize(&frame);
        }
        tokio::task::spawn_blocking(move || super::captcha::recognize(&frame))
            .await
            .ok()
            .flatten()
    }
}
