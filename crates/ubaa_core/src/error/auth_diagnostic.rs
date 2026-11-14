//! 登录失败的本地诊断，不携带响应正文或账号。

/// 已执行的登录阶段。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthStage {
    /// 获取登录页。
    LoginPage,
    /// 提交登录信息。
    Submission,
    /// 处理认证跳转。
    Redirect,
    /// 获取或提交验证码。
    Captcha,
    /// 核验学校身份。
    IdentityValidation,
}

impl AuthStage {
    /// 本地诊断使用的固定名称。
    #[must_use]
    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::LoginPage => "login_page",
            Self::Submission => "submission",
            Self::Redirect => "redirect",
            Self::Captcha => "captcha",
            Self::IdentityValidation => "identity_validation",
        }
    }
}

/// 本地分支已确认的失败原因。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthReason {
    /// 登录页不满足已验证结构。
    LoginPageInvalid,
    /// 认证跳转不满足已验证规则。
    RedirectInvalid,
    /// 学校身份响应无法核验。
    IdentityResponseInvalid,
    /// 返回身份与本次登录账号不匹配。
    IdentityMismatch,
    /// 验证挑战已经失效。
    CaptchaExpired,
    /// 验证未通过，不能区分密码与验证码错误。
    VerificationIncomplete,
}

impl AuthReason {
    /// 固定原因名称与所属阶段。
    #[must_use]
    pub const fn diagnostic(self) -> AuthDiagnostic {
        let stage = match self {
            Self::LoginPageInvalid => AuthStage::LoginPage,
            Self::RedirectInvalid => AuthStage::Redirect,
            Self::IdentityResponseInvalid | Self::IdentityMismatch => AuthStage::IdentityValidation,
            Self::CaptchaExpired | Self::VerificationIncomplete => AuthStage::Captcha,
        };
        AuthDiagnostic {
            stage,
            reason: Some(self),
        }
    }

    /// 本地诊断使用的固定名称。
    #[must_use]
    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::LoginPageInvalid => "login_page_invalid",
            Self::RedirectInvalid => "redirect_invalid",
            Self::IdentityResponseInvalid => "identity_response_invalid",
            Self::IdentityMismatch => "identity_mismatch",
            Self::CaptchaExpired => "captcha_expired",
            Self::VerificationIncomplete => "verification_incomplete",
        }
    }
}

/// 只在本进程与 Bridge 中传播，不扩展 CLI 的错误序列化合同。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AuthDiagnostic {
    /// 失败阶段。
    pub stage: AuthStage,
    /// 已确认的原因；未知时为空。
    pub reason: Option<AuthReason>,
}
