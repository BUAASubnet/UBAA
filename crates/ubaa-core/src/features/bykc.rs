//! 博雅课程只读响应解析。
#![allow(clippy::missing_errors_doc)]
#![allow(dead_code)]

use crate::connection::from_webvpn_url;
use crate::domain::{
    BykcActionResult, BykcChosenCourse, BykcCourse, BykcCourseCategory, BykcCoursePage,
    BykcCourseStatus, BykcCourseSubCategory, BykcSignConfig, BykcSignPoint, BykcSignRequest,
    BykcStatistic, BykcStatistics, BykcUserProfile,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{Local, NaiveDateTime};
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
    all: bool,
) -> Result<BykcCoursePage> {
    parse_courses_at(
        &wrap(
            &request_api(
                runtime,
                "queryStudentSemesterCourseByPage",
                serde_json::json!({"pageNumber":page,"pageSize":size}),
            )
            .await?,
        ),
        all,
        Local::now().naive_local(),
    )
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
) -> Result<Vec<BykcChosenCourse>> {
    let config = request_api(runtime, "getAllConfig", serde_json::json!({})).await?;
    let (start, end) = resolve_current_semester(&config, Local::now().naive_local())?;
    parse_chosen_courses(&wrap(
        &request_api(
            runtime,
            "queryChosenCourse",
            serde_json::json!({"startDate":start,"endDate":end}),
        )
        .await?,
    ))
}

fn resolve_current_semester(config: &Value, now: NaiveDateTime) -> Result<(String, String)> {
    let semesters = config
        .get("semester")
        .and_then(Value::as_array)
        .filter(|items| !items.is_empty())
        .ok_or_else(|| error("无法获取当前学期信息"))?;
    let parse = |value: Option<&Value>| {
        value.and_then(Value::as_str).and_then(|text| {
            NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M:%S")
                .or_else(|_| NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S"))
                .ok()
        })
    };
    let fallback = NaiveDateTime::parse_from_str("1970-01-01T00:00:00", "%Y-%m-%dT%H:%M:%S")
        .expect("固定回退时间必须有效");
    let selected = semesters
        .iter()
        .find(|semester| {
            let start = parse(semester.get("semesterStartDate"));
            let end = parse(semester.get("semesterEndDate"));
            matches!((start, end), (Some(start), Some(end)) if start <= now && now <= end)
        })
        .or_else(|| {
            semesters
                .iter()
                .max_by_key(|semester| parse(semester.get("semesterEndDate")).unwrap_or(fallback))
        })
        .ok_or_else(|| error("无法获取当前学期信息"))?;
    let required = |field| {
        selected
            .get(field)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| error("无法获取当前学期信息"))
    };
    Ok((required("semesterStartDate")?, required("semesterEndDate")?))
}
pub(crate) async fn get_statistics(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcStatistics> {
    parse_statistics(&wrap(
        &request_api(runtime, "queryStatisticByUserId", serde_json::json!({})).await?,
    ))
}

/// 选课写操作。
pub(crate) async fn select_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    if course_id <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识必须为正数",
        ));
    }
    let value = request_api(
        runtime,
        "choseCourse",
        serde_json::json!({"courseId": course_id}),
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("选课成功")
            .to_owned(),
    })
}

/// 退选写操作。
pub(crate) async fn deselect_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    if course_id <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识必须为正数",
        ));
    }
    let value = request_api(
        runtime,
        "delChosenCourse",
        serde_json::json!({"id": course_id}),
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("退选成功")
            .to_owned(),
    })
}

/// 博雅签到或签退写操作。
pub(crate) async fn sign_course(
    runtime: &mut crate::runtime::ClientRuntime,
    request: BykcSignRequest,
) -> Result<BykcActionResult> {
    if request.course_id <= 0 || !matches!(request.sign_type, 1 | 2) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识或签到类型无效",
        ));
    }
    let value = request_api(
        runtime,
        "signCourseByUser",
        serde_json::to_value(&request).map_err(|_| error("博雅签到参数无效"))?,
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or(if request.sign_type == 1 {
                "签到成功"
            } else {
                "签退成功"
            })
            .to_owned(),
    })
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

fn course(value: &Value, now: NaiveDateTime) -> Result<BykcCourse> {
    let m = value.as_object().ok_or_else(|| error("博雅课程字段无效"))?;
    let course_start_date = string(m, "courseStartDate");
    let course_select_start_date = string(m, "courseSelectStartDate");
    let course_select_end_date = string(m, "courseSelectEndDate");
    let selected = m.get("selected").and_then(Value::as_bool);
    let course_max_count = int(m, "courseMaxCount");
    let course_current_count = int(m, "courseCurrentCount");
    let status = course_status(
        course_start_date.as_deref(),
        course_select_start_date.as_deref(),
        course_select_end_date.as_deref(),
        selected,
        course_current_count,
        course_max_count,
        now,
    );
    Ok(BykcCourse {
        id: m
            .get("id")
            .and_then(Value::as_i64)
            .ok_or_else(|| error("博雅课程缺少标识"))?,
        course_name: string(m, "courseName").ok_or_else(|| error("博雅课程缺少名称"))?,
        course_position: string(m, "coursePosition"),
        course_teacher: string(m, "courseTeacher"),
        course_start_date,
        course_end_date: string(m, "courseEndDate"),
        course_select_start_date,
        course_select_end_date,
        course_cancel_end_date: string(m, "courseCancelEndDate"),
        course_max_count,
        course_current_count,
        status,
        selected,
    })
}

fn parse_datetime(value: Option<&str>) -> Option<NaiveDateTime> {
    let value = value?.trim();
    [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S%.f",
        "%Y-%m-%dT%H:%M:%S%.f",
    ]
    .into_iter()
    .find_map(|format| NaiveDateTime::parse_from_str(value, format).ok())
}

#[allow(clippy::too_many_arguments)]
fn course_status(
    course_start: Option<&str>,
    select_start: Option<&str>,
    select_end: Option<&str>,
    selected: Option<bool>,
    current_count: Option<i32>,
    max_count: Option<i32>,
    now: NaiveDateTime,
) -> BykcCourseStatus {
    if parse_datetime(course_start).is_some_and(|value| now > value) {
        BykcCourseStatus::Expired
    } else if selected == Some(true) {
        BykcCourseStatus::Selected
    } else if parse_datetime(select_end).is_some_and(|value| now > value) {
        BykcCourseStatus::Ended
    } else if current_count
        .zip(max_count)
        .is_some_and(|(current, max)| current >= max)
    {
        BykcCourseStatus::Full
    } else if parse_datetime(select_start).is_some_and(|value| now < value) {
        BykcCourseStatus::Preview
    } else {
        BykcCourseStatus::Available
    }
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
    parse_courses_at(body, true, Local::now().naive_local())
}

fn parse_courses_at(body: &str, all: bool, now: NaiveDateTime) -> Result<BykcCoursePage> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅课程分页结构无效"))?;
    let content = m
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| error("博雅课程分页缺少列表"))?
        .iter()
        .map(|value| course(value, now))
        .collect::<Result<Vec<_>>>()?;
    let content = content
        .into_iter()
        .filter(|course| {
            all || !matches!(
                course.status,
                BykcCourseStatus::Expired | BykcCourseStatus::Ended
            )
        })
        .collect();
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
    course(&envelope(body)?, Local::now().naive_local())
}

/// 解析已选课程列表。
pub fn parse_chosen_courses(body: &str) -> Result<Vec<BykcChosenCourse>> {
    parse_chosen_courses_at(body, Local::now().naive_local())
}

fn parse_chosen_courses_at(body: &str, now: NaiveDateTime) -> Result<Vec<BykcChosenCourse>> {
    let payload = envelope(body)?;
    payload
        .as_array()
        .or_else(|| payload.get("courseList").and_then(Value::as_array))
        .ok_or_else(|| error("博雅已选课程结构无效"))?
        .iter()
        .map(|v| {
            let m = v.as_object().ok_or_else(|| error("博雅已选课程字段无效"))?;
            let course = m.get("courseInfo").and_then(Value::as_object);
            let sign_config = course
                .and_then(|course| string(course, "courseSignConfig"))
                .as_deref()
                .and_then(parse_sign_config);
            let checkin = int(m, "checkin").unwrap_or_default();
            let pass = int(m, "pass");
            let can_sign = pass != Some(1)
                && matches!(checkin, 0)
                && sign_config.as_ref().is_some_and(|config| {
                    is_within_window(
                        config.sign_start_date.as_deref(),
                        config.sign_end_date.as_deref(),
                        now,
                    )
                });
            let can_sign_out = pass != Some(1)
                && matches!(checkin, 0 | 5 | 6)
                && sign_config.as_ref().is_some_and(|config| {
                    is_within_window(
                        config.sign_out_start_date.as_deref(),
                        config.sign_out_end_date.as_deref(),
                        now,
                    )
                });
            Ok(BykcChosenCourse {
                id: m
                    .get("id")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| error("博雅选课记录缺少标识"))?,
                course_id: course
                    .and_then(|course| course.get("id"))
                    .and_then(Value::as_i64)
                    .unwrap_or_default(),
                course_name: course
                    .and_then(|course| string(course, "courseName"))
                    .unwrap_or_else(|| "未知课程".to_owned()),
                course_position: course
                    .and_then(|course| normalized_string(course, "coursePosition")),
                course_teacher: course
                    .and_then(|course| normalized_string(course, "courseTeacher")),
                course_start_date: course.and_then(|course| string(course, "courseStartDate")),
                course_end_date: course.and_then(|course| string(course, "courseEndDate")),
                select_date: string(m, "selectDate"),
                course_cancel_end_date: course
                    .and_then(|course| string(course, "courseCancelEndDate")),
                category: course
                    .and_then(|course| nested_kind_name(course, "courseNewKind1"))
                    .map(parse_category),
                sub_category: course
                    .and_then(|course| nested_kind_name(course, "courseNewKind2"))
                    .map(parse_sub_category),
                checkin,
                score: int(m, "score"),
                pass,
                can_sign,
                can_sign_out,
                sign_config,
                course_sign_type: course.and_then(|course| int(course, "courseSignType")),
                homework: normalized_string(m, "homework"),
                homework_attachment_name: None,
                homework_attachment_path: None,
                sign_info: normalized_string(m, "signInfo"),
            })
        })
        .collect()
}

fn normalized_string(map: &Map<String, Value>, key: &str) -> Option<String> {
    string(map, key)
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn nested_kind_name<'a>(map: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    map.get(key)
        .and_then(Value::as_object)
        .and_then(|kind| kind.get("kindName"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn parse_category(value: &str) -> BykcCourseCategory {
    match value {
        "博雅课程" => BykcCourseCategory::Boya,
        _ => BykcCourseCategory::Unknown,
    }
}

fn parse_sub_category(value: &str) -> BykcCourseSubCategory {
    match value {
        "德育" => BykcCourseSubCategory::Moral,
        "美育" => BykcCourseSubCategory::Aesthetic,
        "劳动教育" => BykcCourseSubCategory::Labor,
        "安全健康" => BykcCourseSubCategory::SafetyHealth,
        "其他方面" => BykcCourseSubCategory::Other,
        _ => BykcCourseSubCategory::Unknown,
    }
}

fn parse_sign_config(raw: &str) -> Option<BykcSignConfig> {
    let map = serde_json::from_str::<Value>(raw).ok()?;
    let map = map.as_object()?;
    let sign_points = map
        .get("signPointList")
        .and_then(Value::as_array)
        .map_or(&[][..], Vec::as_slice)
        .iter()
        .filter_map(|point| {
            let point = point.as_object()?;
            Some(BykcSignPoint {
                lat: point.get("lat")?.as_f64()?,
                lng: point.get("lng")?.as_f64()?,
                radius: point
                    .get("radius")
                    .and_then(Value::as_f64)
                    .unwrap_or_default(),
            })
        })
        .collect();
    Some(BykcSignConfig {
        sign_start_date: string(map, "signStartDate"),
        sign_end_date: string(map, "signEndDate"),
        sign_out_start_date: string(map, "signOutStartDate"),
        sign_out_end_date: string(map, "signOutEndDate"),
        sign_points,
    })
}

fn is_within_window(start: Option<&str>, end: Option<&str>, now: NaiveDateTime) -> bool {
    start
        .and_then(|start| parse_datetime(Some(start)))
        .zip(end.and_then(|end| parse_datetime(Some(end))))
        .is_some_and(|(start, end)| start <= now && now <= end)
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

    #[test]
    fn 课程分页默认过滤已过期和选课结束项目() {
        let body = serde_json::json!({
            "status": "0",
            "data": {
                "content": [
                    {"id": 1, "courseName": "已开课", "courseStartDate": "2026-01-01 08:00:00"},
                    {"id": 2, "courseName": "已结束选课", "courseStartDate": "2026-09-01 08:00:00", "courseSelectEndDate": "2026-01-01 08:00:00"},
                    {"id": 3, "courseName": "可选", "courseStartDate": "2026-09-01 08:00:00", "courseSelectEndDate": "2026-08-01 08:00:00"}
                ],
                "totalElements": 3,
                "totalPages": 1,
                "size": 20,
                "number": 1
            }
        })
        .to_string();
        let now = NaiveDateTime::parse_from_str("2026-07-01 12:00:00", "%Y-%m-%d %H:%M:%S")
            .expect("解析固定时间");

        let filtered = parse_courses_at(&body, false, now).expect("解析默认课程分页");
        let all = parse_courses_at(&body, true, now).expect("解析全部课程分页");

        assert_eq!(filtered.content.len(), 1);
        assert_eq!(filtered.content[0].status, BykcCourseStatus::Available);
        assert_eq!(filtered.total_elements, 3);
        assert_eq!(all.content.len(), 3);
    }

    #[test]
    fn 已选课程自动选择当前学期并回退到最新学期() {
        let config = serde_json::json!({
            "semester": [
                {"semesterStartDate": "2025-09-01 00:00:00", "semesterEndDate": "2026-01-31 23:59:59"},
                {"semesterStartDate": "2026-02-01 00:00:00", "semesterEndDate": "2026-07-31 23:59:59"}
            ]
        });
        let current = NaiveDateTime::parse_from_str("2026-03-01 12:00:00", "%Y-%m-%d %H:%M:%S")
            .expect("解析固定时间");
        let after = NaiveDateTime::parse_from_str("2026-08-01 12:00:00", "%Y-%m-%d %H:%M:%S")
            .expect("解析固定时间");

        assert_eq!(
            resolve_current_semester(&config, current).expect("选择当前学期"),
            (
                "2026-02-01 00:00:00".to_owned(),
                "2026-07-31 23:59:59".to_owned()
            )
        );
        assert_eq!(
            resolve_current_semester(&config, after).expect("选择最新学期"),
            (
                "2026-02-01 00:00:00".to_owned(),
                "2026-07-31 23:59:59".to_owned()
            )
        );
        assert_eq!(
            resolve_current_semester(&serde_json::json!({"semester": []}), current)
                .expect_err("空学期必须失败")
                .message,
            "无法获取当前学期信息"
        );
    }

    #[test]
    fn 已选课程展开课程签到和作业字段() {
        let body = serde_json::json!({
            "status": "0",
            "data": [{
                "id": 9,
                "selectDate": "2026-02-20 12:00:00",
                "checkin": 5,
                "score": 88,
                "pass": 0,
                "homework": "提交学习报告",
                "signInfo": "已签到",
                "courseInfo": {
                    "id": 42,
                    "courseName": "艺术鉴赏",
                    "coursePosition": "学院路校区",
                    "courseTeacher": "教师甲",
                    "courseStartDate": "2026-03-01 08:00:00",
                    "courseEndDate": "2026-03-01 10:00:00",
                    "courseCancelEndDate": "2026-02-28 18:00:00",
                    "courseNewKind1": {"kindName": "博雅课程"},
                    "courseNewKind2": {"kindName": "美育"},
                    "courseSignType": 1,
                    "courseSignConfig": "{\"signStartDate\":\"2026-03-01 07:50:00\",\"signEndDate\":\"2026-03-01 08:10:00\",\"signOutStartDate\":\"2026-03-01 09:50:00\",\"signOutEndDate\":\"2026-03-01 10:10:00\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"
                }
            }]
        }).to_string();

        let record = parse_chosen_courses_at(
            &body,
            NaiveDateTime::parse_from_str("2026-03-01 10:00:00", "%Y-%m-%d %H:%M:%S")
                .expect("解析固定时间"),
        )
        .expect("解析已选课程")
        .remove(0);

        assert_eq!(record.course_id, 42);
        assert_eq!(record.course_name, "艺术鉴赏");
        assert_eq!(record.category, Some(BykcCourseCategory::Boya));
        assert_eq!(record.sub_category, Some(BykcCourseSubCategory::Aesthetic));
        assert_eq!(record.checkin, 5);
        assert_eq!(record.pass, Some(0));
        assert!(!record.can_sign);
        assert!(record.can_sign_out);
        assert_eq!(record.sign_config.expect("签到配置").sign_points.len(), 1);
        assert_eq!(record.homework.as_deref(), Some("提交学习报告"));
        assert_eq!(record.sign_info.as_deref(), Some("已签到"));
    }

    #[test]
    fn 已选课程接受冻结的_course_list_响应包装() {
        let body = serde_json::json!({
            "status": "0",
            "data": {
                "courseList": [{
                    "id": 9001,
                    "courseInfo": {"id": 9527, "courseName": "耕趣农场劳动课"}
                }]
            }
        })
        .to_string();
        let result = parse_chosen_courses(&body).expect("冻结 courseList 包装应可解析");
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, 9001);
        assert_eq!(result[0].course_id, 9527);
    }
}
