//! 博雅课程只读响应解析。
#![allow(clippy::missing_errors_doc)]
#![allow(dead_code)]

use crate::connection::from_webvpn_url;
use crate::domain::{
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistic, BykcStatistics, BykcUserProfile,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockDecryptMut, BlockEncryptMut, KeyInit, block_padding::Pkcs7};
use rand::Rng;
use rsa::{Pkcs1v15Encrypt, RsaPublicKey, pkcs8::DecodePublicKey};
use serde_json::{Map, Value};
use sha1::{Digest, Sha1};

const RSA_PUBLIC_KEY_BASE64: &str = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlHMQ3B5GsWnCe7Nlo1YiG/YmHdlOiKOST5aRm4iaqYSvhvWmwcigoyWTM+8bv2+sf6nQBRDWTY4KmNV7DBk1eDnTIQo6ENA31k5/tYCLEXgjPbEjCK9spiyB62fCT6cqOhbamJB0lcDJRO6Vo1m3dy+fD0jbxfDVBBNtyltIsDQIDAQAB";
const KEY_CHARS: &[u8] = b"ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678";
const BASE_URL: &str = "https://bykc.buaa.edu.cn";
const LOGIN_URL: &str = "https://bykc.buaa.edu.cn/sscv/cas/login";

/// 路线内存中的博雅业务令牌。
#[derive(Clone)]
pub(crate) struct BykcCredential {
    pub(crate) token: String,
}

impl std::fmt::Debug for BykcCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BykcCredential")
            .field("token", &"[已隐藏]")
            .finish()
    }
}

pub(crate) struct EncryptedRequest {
    pub(crate) encrypted_data: String,
    pub(crate) ak: String,
    pub(crate) sk: String,
    pub(crate) ts: String,
    aes_key: [u8; 16],
}

pub(crate) fn encrypt_request(json: &str, timestamp: i64) -> Result<EncryptedRequest> {
    let mut key = [0_u8; 16];
    let mut rng = rand::thread_rng();
    for byte in &mut key {
        *byte = KEY_CHARS[rng.gen_range(0..KEY_CHARS.len())];
    }
    encrypt_request_with_key(json, timestamp, key)
}

fn encrypt_request_with_key(json: &str, timestamp: i64, key: [u8; 16]) -> Result<EncryptedRequest> {
    let cipher = aes::Aes128::new_from_slice(&key).map_err(|_| error("博雅 AES 密钥无效"))?;
    let mut buffer = json.as_bytes().to_vec();
    let length = buffer.len();
    buffer.resize(length + 16, 0);
    let encrypted = cipher
        .encrypt_padded_mut::<Pkcs7>(&mut buffer, length)
        .map_err(|_| error("博雅请求加密失败"))?;
    let public_der = STANDARD
        .decode(RSA_PUBLIC_KEY_BASE64)
        .map_err(|_| error("博雅 RSA 公钥无效"))?;
    let public =
        RsaPublicKey::from_public_key_der(&public_der).map_err(|_| error("博雅 RSA 公钥无效"))?;
    let digest = format!("{:x}", Sha1::digest(json.as_bytes()));
    let mut rng = rand::thread_rng();
    let ak = public
        .encrypt(&mut rng, Pkcs1v15Encrypt, &key)
        .map_err(|_| error("博雅 AES 密钥加密失败"))?;
    let sk = public
        .encrypt(&mut rng, Pkcs1v15Encrypt, digest.as_bytes())
        .map_err(|_| error("博雅摘要加密失败"))?;
    Ok(EncryptedRequest {
        encrypted_data: STANDARD.encode(encrypted),
        ak: STANDARD.encode(ak),
        sk: STANDARD.encode(sk),
        ts: timestamp.to_string(),
        aes_key: key,
    })
}

pub(crate) fn decrypt_response(value: &str, key: &[u8; 16]) -> Result<String> {
    let mut data = STANDARD
        .decode(value.trim_matches('"'))
        .map_err(|_| error("博雅响应密文无效"))?;
    let cipher = aes::Aes128::new_from_slice(key).map_err(|_| error("博雅 AES 密钥无效"))?;
    let plain = cipher
        .decrypt_padded_mut::<Pkcs7>(&mut data)
        .map_err(|_| error("博雅响应解密失败"))?;
    String::from_utf8(plain.to_vec()).map_err(|_| error("博雅响应文本无效"))
}

/// 通过 CAS 跳转获取博雅业务令牌。
pub(crate) async fn ensure_login(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcCredential> {
    super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(value) = state.bykc.credential() {
        return Ok(value);
    }
    let _guard = state.bykc.login_guard().await;
    if let Some(value) = state.bykc.credential() {
        return Ok(value);
    }
    let mut current = runtime.url(LOGIN_URL)?;
    for _ in 0..8 {
        let response = runtime.request(HttpRequest::get(current.clone())).await?;
        for candidate in [
            response.final_url.as_str(),
            response
                .headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case("location"))
                .and_then(|(_, v)| v.first())
                .map_or("", |value| value.as_str()),
        ] {
            if let Some(token) = token_from_url(candidate) {
                let value = BykcCredential { token };
                state.bykc.set(value.clone());
                return Ok(value);
            }
        }
        let location = response
            .headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("location"))
            .and_then(|(_, v)| v.first())
            .ok_or_else(|| error("博雅登录跳转缺少目标地址"))?;
        let target = resolve_login_target(&response.final_url, location)?;
        let parsed = url::Url::parse(&target).map_err(|_| error("博雅登录跳转地址无效"))?;
        if !matches!(
            parsed.host_str().unwrap_or_default(),
            "sso.buaa.edu.cn" | "bykc.buaa.edu.cn"
        ) {
            return Err(error("博雅登录跳转到未允许的主机"));
        }
        // 业务跳转必须继续沿用当前路线，WebVPN 模式不能回落到直连地址。
        current = runtime.url(&target)?;
    }
    Err(error("博雅登录跳转次数超过限制"))
}

fn token_from_url(raw: &str) -> Option<String> {
    url::Url::parse(raw)
        .ok()?
        .query_pairs()
        .find(|(k, _)| k == "token")
        .map(|(_, v)| v.into_owned())
        .filter(|v| !v.is_empty())
}

fn resolve_login_target(final_url: &str, location: &str) -> Result<String> {
    let direct_final = from_webvpn_url(final_url)?;
    let direct_location = from_webvpn_url(location)?;
    let base = url::Url::parse(&direct_final).map_err(|_| error("博雅登录跳转地址无效"))?;
    base.join(&direct_location)
        .map(|target| target.to_string())
        .map_err(|_| error("博雅登录跳转地址无效"))
}

async fn request_api(
    runtime: &mut crate::runtime::ClientRuntime,
    api_name: &str,
    payload: Value,
) -> Result<Value> {
    let credential = ensure_login(runtime).await?;
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| error("系统时间无效"))?
        .as_millis();
    let timestamp = i64::try_from(timestamp).map_err(|_| error("系统时间无效"))?;
    let encrypted = encrypt_request(&payload.to_string(), timestamp)?;
    let mut request = HttpRequest::post(
        runtime.url(&format!("{BASE_URL}/sscv/{api_name}"))?,
        encrypted.encrypted_data.clone().into_bytes(),
    );
    request.headers.insert(
        "Content-Type".into(),
        "application/json; charset=UTF-8".into(),
    );
    request
        .headers
        .insert("Accept".into(), "application/json".into());
    request.headers.insert(
        "Referer".into(),
        runtime.url("https://bykc.buaa.edu.cn/system/course-select")?,
    );
    request
        .headers
        .insert("Origin".into(), runtime.url(BASE_URL)?);
    request
        .headers
        .insert("auth_token".into(), credential.token.clone());
    request.headers.insert("authtoken".into(), credential.token);
    request.headers.insert("ak".into(), encrypted.ak);
    request.headers.insert("sk".into(), encrypted.sk);
    request.headers.insert("ts".into(), encrypted.ts);
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(error("博雅服务暂时不可用"));
    }
    let text = super::body(&response);
    let plain = decrypt_response(&text, &encrypted.aes_key).unwrap_or(text);
    envelope(&plain)
}

fn wrap(value: &Value) -> String {
    serde_json::json!({"status":"0","data":value}).to_string()
}
pub(crate) async fn get_profile(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcUserProfile> {
    parse_profile(&wrap(
        &request_api(runtime, "getUserProfile", serde_json::json!({})).await?,
    ))
}
pub(crate) async fn get_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    size: i32,
) -> Result<BykcCoursePage> {
    parse_courses(&wrap(
        &request_api(
            runtime,
            "queryStudentSemesterCourseByPage",
            serde_json::json!({"pageNumber":page,"pageSize":size}),
        )
        .await?,
    ))
}
pub(crate) async fn get_course_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
) -> Result<BykcCourse> {
    parse_course_detail(&wrap(
        &request_api(runtime, "queryCourseById", serde_json::json!({"id":id})).await?,
    ))
}
pub(crate) async fn get_chosen_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    start: &str,
    end: &str,
) -> Result<Vec<BykcChosenCourse>> {
    parse_chosen_courses(&wrap(
        &request_api(
            runtime,
            "queryChosenCourse",
            serde_json::json!({"startDate":start,"endDate":end}),
        )
        .await?,
    ))
}
pub(crate) async fn get_statistics(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcStatistics> {
    parse_statistics(&wrap(
        &request_api(runtime, "queryStatisticByUserId", serde_json::json!({})).await?,
    ))
}

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn envelope(body: &str) -> Result<Value> {
    let value: Value = serde_json::from_str(body).map_err(|_| error("博雅响应无法解析"))?;
    let object = value.as_object().ok_or_else(|| error("博雅响应结构无效"))?;
    let status = object
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if status != "0" && object.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(error(
            object
                .get("msg")
                .and_then(Value::as_str)
                .unwrap_or("博雅请求失败"),
        ));
    }
    object
        .get("data")
        .or_else(|| object.get("result"))
        .cloned()
        .ok_or_else(|| error("博雅响应缺少数据"))
}

fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key).and_then(Value::as_str).map(str::to_owned)
}
fn int(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            map.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
}

fn course(value: &Value) -> Result<BykcCourse> {
    let m = value.as_object().ok_or_else(|| error("博雅课程字段无效"))?;
    Ok(BykcCourse {
        id: m
            .get("id")
            .and_then(Value::as_i64)
            .ok_or_else(|| error("博雅课程缺少标识"))?,
        course_name: string(m, "courseName").ok_or_else(|| error("博雅课程缺少名称"))?,
        course_position: string(m, "coursePosition"),
        course_teacher: string(m, "courseTeacher"),
        course_start_date: string(m, "courseStartDate"),
        course_end_date: string(m, "courseEndDate"),
        course_max_count: int(m, "courseMaxCount"),
        course_current_count: int(m, "courseCurrentCount"),
        selected: m.get("selected").and_then(Value::as_bool),
    })
}

/// 解析用户资料。
pub fn parse_profile(body: &str) -> Result<BykcUserProfile> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅资料结构无效"))?;
    Ok(BykcUserProfile {
        id: m
            .get("id")
            .and_then(Value::as_i64)
            .ok_or_else(|| error("博雅资料缺少用户标识"))?,
        employee_id: string(&m, "employeeId"),
        real_name: string(&m, "realName"),
        student_no: string(&m, "studentNo"),
        college_name: m
            .get("college")
            .and_then(Value::as_object)
            .and_then(|v| string(v, "collegeName")),
    })
}

/// 解析课程分页。
pub fn parse_courses(body: &str) -> Result<BykcCoursePage> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅课程分页结构无效"))?;
    let content = m
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| error("博雅课程分页缺少列表"))?
        .iter()
        .map(course)
        .collect::<Result<Vec<_>>>()?;
    Ok(BykcCoursePage {
        content,
        total_elements: int(&m, "totalElements").unwrap_or_default(),
        total_pages: int(&m, "totalPages").unwrap_or_default(),
        size: int(&m, "size").unwrap_or_default(),
        number: int(&m, "number").unwrap_or_default(),
    })
}

/// 解析课程详情。
pub fn parse_course_detail(body: &str) -> Result<BykcCourse> {
    course(&envelope(body)?)
}

/// 解析已选课程列表。
pub fn parse_chosen_courses(body: &str) -> Result<Vec<BykcChosenCourse>> {
    envelope(body)?
        .as_array()
        .ok_or_else(|| error("博雅已选课程结构无效"))?
        .iter()
        .map(|v| {
            let m = v.as_object().ok_or_else(|| error("博雅已选课程字段无效"))?;
            Ok(BykcChosenCourse {
                id: m
                    .get("id")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| error("博雅选课记录缺少标识"))?,
                course_id: m.get("courseId").and_then(Value::as_i64),
                course_name: string(m, "courseName"),
                select_date: string(m, "selectDate"),
                checkin: int(m, "checkin"),
                score: int(m, "score"),
            })
        })
        .collect()
}

/// 解析修读统计。
pub fn parse_statistics(body: &str) -> Result<BykcStatistics> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅统计结构无效"))?;
    let categories = m
        .get("categories")
        .or_else(|| m.get("list"))
        .and_then(Value::as_array)
        .map_or(&[][..], |v| v)
        .iter()
        .filter_map(Value::as_object)
        .map(|v| BykcStatistic {
            category_name: string(v, "categoryName"),
            sub_category_name: string(v, "subCategoryName"),
            required_count: int(v, "requiredCount"),
            passed_count: int(v, "passedCount"),
            qualified: v.get("isQualified").and_then(Value::as_bool),
        })
        .collect();
    Ok(BykcStatistics {
        total_valid_count: int(&m, "totalValidCount"),
        categories,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::to_webvpn_url;

    #[test]
    fn webvpn_绝对跳转先还原为直连目标() {
        let final_url = to_webvpn_url(LOGIN_URL).expect("包装博雅登录地址");
        let target = to_webvpn_url("https://bykc.buaa.edu.cn/cas-login?token=已脱敏")
            .expect("包装博雅回调地址");

        assert_eq!(
            resolve_login_target(&final_url, &target).expect("解析 WebVPN 跳转"),
            "https://bykc.buaa.edu.cn/cas-login?token=%E5%B7%B2%E8%84%B1%E6%95%8F"
        );
    }

    #[test]
    fn webvpn_相对跳转按还原后的业务地址解析() {
        let final_url = to_webvpn_url(LOGIN_URL).expect("包装博雅登录地址");

        assert_eq!(
            resolve_login_target(&final_url, "/cas-login?token=已脱敏")
                .expect("解析 WebVPN 相对跳转"),
            "https://bykc.buaa.edu.cn/cas-login?token=%E5%B7%B2%E8%84%B1%E6%95%8F"
        );
    }

    #[test]
    fn 冻结摘要与加密正文向量保持一致() {
        assert_eq!(
            format!("{:x}", Sha1::digest(b"abc")),
            "a9993e364706816aba3e25717850c26c9cd0d89d"
        );
        let request = encrypt_request_with_key(
            r#"{"pageNumber":1,"pageSize":20}"#,
            1_700_000_000_000,
            *b"ABCDEFGHJKMNPQRS",
        )
        .unwrap();
        assert_eq!(request.ts, "1700000000000");
        assert_eq!(STANDARD.decode(&request.ak).unwrap().len(), 128);
        assert_eq!(STANDARD.decode(&request.sk).unwrap().len(), 128);
        assert_eq!(
            decrypt_response(&request.encrypted_data, &request.aes_key).unwrap(),
            r#"{"pageNumber":1,"pageSize":20}"#
        );
    }

    #[test]
    fn 业务凭据调试输出隐藏令牌() {
        let text = format!(
            "{:?}",
            BykcCredential {
                token: "secret".into()
            }
        );
        assert!(!text.contains("secret"));
        assert!(text.contains("已隐藏"));
    }
}
