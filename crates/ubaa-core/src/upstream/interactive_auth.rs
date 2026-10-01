//! 只接受冻结旧版已实现的图像验证码配置。

use crate::error::Result;
use regex::Regex;
use std::sync::OnceLock;

static CONFIG: OnceLock<Regex> = OnceLock::new();

pub(crate) struct ImageCaptchaPage {
    pub(crate) id: String,
    pub(crate) execution: String,
}

pub(crate) fn parse_image_captcha(html: &str) -> Result<Option<ImageCaptchaPage>> {
    let lower = html.to_ascii_lowercase();
    if !lower.contains("config.captcha") {
        return if super::has_unsupported_login_step(html) {
            Err(unsupported())
        } else {
            Ok(None)
        };
    }
    let pattern = CONFIG.get_or_init(|| {
        Regex::new(
            r#"config\.captcha\s*=\s*\{\s*type:\s*['"]([^'"]+)['"],\s*id:\s*['"]([^'"]+)['"]\s*\}"#,
        )
        .expect("固定验证码配置正则")
    });
    if lower.matches("config.captcha").count() != 1 {
        return Err(unsupported());
    }
    let found = pattern.captures(html).ok_or_else(unsupported)?;
    let id = found.get(2).ok_or_else(unsupported)?.as_str();
    if &found[1] != "image" || id.trim().is_empty() || id.len() > 4096 {
        return Err(unsupported());
    }
    let document = scraper::Html::parse_document(html);
    let execution_selector = super::selector("input[name=execution]");
    let mut executions = document.select(&execution_selector);
    let execution = executions
        .next()
        .and_then(|value| value.value().attr("value"))
        .ok_or_else(unsupported)?;
    if executions.next().is_some() || execution.trim().is_empty() || execution.len() > 4096 {
        return Err(unsupported());
    }
    let without_config = pattern.replace(html, "");
    if super::has_unsupported_login_controls(&without_config, true) {
        return Err(unsupported());
    }
    Ok(Some(ImageCaptchaPage {
        id: id.to_owned(),
        execution: execution.to_owned(),
    }))
}

fn unsupported() -> crate::error::UbaaError {
    super::upstream_changed("SSO 登录页要求未支持的验证步骤")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_legacy_image_config_is_supported() {
        let page = r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-execution"></form><script>config.captcha = { type: 'image', id: 'synthetic-id' }</script>"#;
        let parsed = parse_image_captcha(page)
            .expect("已证形状必须识别")
            .expect("应存在图像挑战");
        assert_eq!(parsed.id, "synthetic-id");
        assert_eq!(parsed.execution, "synthetic-execution");
    }

    #[test]
    fn unknown_or_ambiguous_interactions_stay_closed() {
        let page = r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-execution"></form><script>config.captcha = { type: 'image', id: 'synthetic-id' }</script>"#;
        for bad in [
            page.replace("'image'", "'slider'"),
            page.replace("'synthetic-id'", "''"),
            page.replace("synthetic-execution", " "),
            page.replace("</form>", "<input name=execution value=duplicate></form>"),
            page.replace("</form>", "<input name=otp></form>"),
            page.replace(
                "</form>",
                "<input type=hidden name=otp value=synthetic></form>",
            ),
            format!("{page}<form><input name=otp value=synthetic></form>"),
            page.replace("</form>", "<select name=method></select></form>"),
            format!("{page}<script>config.mfa = {{}}</script>"),
            format!("{page}<script>config.captcha = {{}}</script>"),
            page.replace(
                "type: 'image', id: 'synthetic-id'",
                "id: 'synthetic-id', type: 'image'",
            ),
        ] {
            assert!(parse_image_captcha(&bad).is_err());
        }
    }
}
