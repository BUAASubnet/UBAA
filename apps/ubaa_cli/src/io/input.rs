//! CLI 输入读取、请求输入校验和稳定错误构造。

use std::io::{BufRead, Read, Write};
use std::path::Path;

use serde_json::Value;
use ubaa_core::facade::{
    CgyyReservationSubmitRequest, YgdkClockinSubmitRequest, YgdkPhotoUpload, YgdkSubmitTarget,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) fn prompt_line<R: BufRead, E: Write>(
    input: &mut R,
    stderr: &mut E,
    prompt: &str,
) -> Result<String> {
    loop {
        write!(stderr, "{prompt}").map_err(|_| internal_error("无法写入提示"))?;
        stderr.flush().map_err(|_| internal_error("无法刷新提示"))?;
        let mut value = String::new();
        let read = input
            .read_line(&mut value)
            .map_err(|_| invalid_input("无法读取必填输入"))?;
        if read == 0 {
            return Err(invalid_input("缺少必填输入"));
        }
        let value = value.trim_end_matches(['\r', '\n']).to_string();
        if !value.is_empty() {
            return Ok(value);
        }
        writeln!(stderr, "必须提供一个值。").map_err(|_| internal_error("无法写入提示"))?;
    }
}

pub(crate) fn read_secret_line<R: BufRead>(input: &mut R, missing_message: &str) -> Result<String> {
    let mut value = String::new();
    input
        .read_line(&mut value)
        .map_err(|_| invalid_input(missing_message))?;
    let value = value.trim_end_matches(['\r', '\n']).to_string();
    if value.is_empty() {
        Err(invalid_input(missing_message))
    } else {
        Ok(value)
    }
}

pub(crate) fn read_cgyy_request_stdin() -> Result<CgyyReservationSubmitRequest> {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .map_err(|_| invalid_input("无法读取场馆预约请求"))?;
    parse_cgyy_request(&input)
}

pub(crate) fn parse_cgyy_request(input: &str) -> Result<CgyyReservationSubmitRequest> {
    let value: Value =
        serde_json::from_str(input).map_err(|_| invalid_input("场馆预约请求必须是 JSON 对象"))?;
    if value.as_object().is_some_and(|object| {
        CGYY_PRIVATE_CAPTCHA_FIELDS
            .iter()
            .any(|field| object.contains_key(*field))
    }) {
        return Err(invalid_input(
            "场馆预约请求不得包含由 Core 内部管理的验证码字段",
        ));
    }
    serde_json::from_value(value).map_err(|_| invalid_input("场馆预约请求必须是 JSON 对象"))
}

const CGYY_PRIVATE_CAPTCHA_FIELDS: [&str; 12] = [
    "captchaVerification",
    "captcha_verification",
    "captchaPointJson",
    "captcha_point_json",
    "captchaToken",
    "captcha_token",
    "captchaSecretKey",
    "captcha_secret_key",
    "captchaOriginalImageBase64",
    "captcha_original_image_base64",
    "captchaJigsawImageBase64",
    "captcha_jigsaw_image_base64",
];

pub(crate) fn write_json<W: Write, T: serde::Serialize>(
    stdout: &mut W,
    value: &T,
) -> std::io::Result<()> {
    serde_json::to_writer(&mut *stdout, value)?;
    writeln!(stdout)
}

pub(crate) fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

pub(crate) fn upstream_changed(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

pub(crate) fn build_ygdk_request(
    classify_id: i32,
    item_id: i32,
    start_time: String,
    end_time: String,
    place: Option<String>,
    photo: &Path,
    share_to_square: bool,
) -> Result<YgdkClockinSubmitRequest> {
    if classify_id <= 0 || item_id <= 0 {
        return Err(invalid_input("阳光打卡分类和项目编号必须为正整数"));
    }
    validate_ygdk_time_shape(&start_time, &end_time)?;

    let selected_photo = open_validated_ygdk_photo(photo)?;

    let file_name = photo
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| invalid_input("打卡照片文件名无效"))?;
    validate_ygdk_photo_file_name(file_name)?;
    let extension = photo
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| invalid_input("打卡照片扩展名无效"))?;
    let mime_type = ygdk_photo_mime_type(extension)?;

    let bytes = read_ygdk_photo_after_initial_check(photo, &selected_photo, || {})?;
    let place = place.and_then(|value| {
        let value = value.trim().to_owned();
        (!value.is_empty()).then_some(value)
    });

    Ok(YgdkClockinSubmitRequest {
        target: YgdkSubmitTarget {
            classify_id,
            item_id,
        },
        start_time,
        end_time,
        place,
        share_to_square,
        photo: YgdkPhotoUpload {
            bytes,
            file_name: file_name.to_owned(),
            mime_type,
        },
    })
}

const MAX_YGDK_PHOTO_BYTES: u64 = 10 * 1024 * 1024;

struct ValidatedYgdkPhoto {
    metadata: std::fs::Metadata,
    identity: same_file::Handle,
}

fn open_validated_ygdk_photo(photo: &Path) -> Result<ValidatedYgdkPhoto> {
    let metadata =
        std::fs::symlink_metadata(photo).map_err(|_| invalid_input("无法读取打卡照片"))?;
    if !metadata.file_type().is_file() {
        return Err(invalid_input("打卡照片必须是普通文件"));
    }
    if metadata.len() == 0 || metadata.len() > MAX_YGDK_PHOTO_BYTES {
        return Err(invalid_input("打卡照片大小必须在 1 字节到 10 MiB 之间"));
    }
    // 活句柄固定初检文件身份，Windows 不依赖尚未稳定的 MetadataExt 标识 API。
    let file = std::fs::File::open(photo).map_err(|_| ygdk_photo_changed())?;
    let identity = same_file::Handle::from_file(file).map_err(|_| ygdk_photo_changed())?;
    let opened_metadata = identity
        .as_file()
        .metadata()
        .map_err(|_| ygdk_photo_changed())?;
    if !opened_metadata.file_type().is_file()
        || opened_metadata.len() == 0
        || opened_metadata.len() > MAX_YGDK_PHOTO_BYTES
    {
        return Err(ygdk_photo_changed());
    }
    Ok(ValidatedYgdkPhoto { metadata, identity })
}

fn read_ygdk_photo_after_initial_check(
    photo: &Path,
    selected_photo: &ValidatedYgdkPhoto,
    after_initial_check: impl FnOnce(),
) -> Result<Vec<u8>> {
    after_initial_check();
    let file = std::fs::File::open(photo).map_err(|_| ygdk_photo_changed())?;
    let initial_metadata = &selected_photo.metadata;
    let opened_metadata = file.metadata().map_err(|_| ygdk_photo_changed())?;
    let current_metadata = std::fs::symlink_metadata(photo).map_err(|_| ygdk_photo_changed())?;
    if !initial_metadata.file_type().is_file()
        || !opened_metadata.file_type().is_file()
        || !current_metadata.file_type().is_file()
        || opened_metadata.len() == 0
        || opened_metadata.len() > MAX_YGDK_PHOTO_BYTES
        || current_metadata.len() == 0
        || current_metadata.len() > MAX_YGDK_PHOTO_BYTES
    {
        return Err(ygdk_photo_changed());
    }
    // 保留 Unix 原有两次 lstat 身份比较，不扩大 lstat 与打开路径之间的竞态窗口。
    #[cfg(unix)]
    if !same_ygdk_photo_identity(initial_metadata, &opened_metadata)
        || !same_ygdk_photo_identity(&opened_metadata, &current_metadata)
    {
        return Err(ygdk_photo_changed());
    }
    let opened_identity = same_file::Handle::from_file(file).map_err(|_| ygdk_photo_changed())?;
    let current_file = std::fs::File::open(photo).map_err(|_| ygdk_photo_changed())?;
    let current_identity =
        same_file::Handle::from_file(current_file).map_err(|_| ygdk_photo_changed())?;
    if selected_photo.identity != opened_identity || opened_identity != current_identity {
        return Err(ygdk_photo_changed());
    }
    read_ygdk_photo_bytes(opened_identity.as_file())
}

fn read_ygdk_photo_bytes(reader: impl Read) -> Result<Vec<u8>> {
    let mut reader = reader.take(MAX_YGDK_PHOTO_BYTES + 1);
    let mut bytes = Vec::new();
    reader
        .read_to_end(&mut bytes)
        .map_err(|_| invalid_input("无法读取打卡照片"))?;
    if bytes.is_empty() || bytes.len() as u64 > MAX_YGDK_PHOTO_BYTES {
        return Err(invalid_input("打卡照片大小必须在 1 字节到 10 MiB 之间"));
    }
    Ok(bytes)
}

#[cfg(unix)]
fn same_ygdk_photo_identity(left: &std::fs::Metadata, right: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;

    left.dev() == right.dev() && left.ino() == right.ino()
}

fn ygdk_photo_changed() -> UbaaError {
    invalid_input("打卡照片在读取期间发生变化")
}

fn ygdk_photo_mime_type(extension: &str) -> Result<String> {
    if extension.is_empty()
        || !extension.is_ascii()
        || !extension.bytes().all(is_http_token_character)
    {
        return Err(invalid_input("打卡照片扩展名无效"));
    }
    let subtype = extension.to_ascii_lowercase();
    let subtype = if subtype == "jpg" { "jpeg" } else { &subtype };
    Ok(format!("image/{subtype}"))
}

const fn is_http_token_character(value: u8) -> bool {
    value.is_ascii_alphanumeric()
        || matches!(
            value,
            b'!' | b'#'
                | b'$'
                | b'%'
                | b'&'
                | b'\''
                | b'*'
                | b'+'
                | b'-'
                | b'.'
                | b'^'
                | b'_'
                | b'`'
                | b'|'
                | b'~'
        )
}

fn validate_ygdk_time_shape(start_time: &str, end_time: &str) -> Result<()> {
    let Some((start_date, start_minute)) = parse_ygdk_time_shape(start_time) else {
        return Err(invalid_input("阳光打卡时间必须使用 yyyy-MM-dd HH:mm 格式"));
    };
    let Some((end_date, end_minute)) = parse_ygdk_time_shape(end_time) else {
        return Err(invalid_input("阳光打卡时间必须使用 yyyy-MM-dd HH:mm 格式"));
    };
    if start_date != end_date || end_minute <= start_minute {
        return Err(invalid_input(
            "阳光打卡开始和结束时间必须在同一天且结束时间更晚",
        ));
    }
    Ok(())
}

fn parse_ygdk_time_shape(value: &str) -> Option<([u8; 10], u16)> {
    let bytes = value.as_bytes();
    if bytes.len() != 16
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes[10] != b' '
        || bytes[13] != b':'
    {
        return None;
    }
    for (index, byte) in bytes.iter().enumerate() {
        if !matches!(index, 4 | 7 | 10 | 13) && !byte.is_ascii_digit() {
            return None;
        }
    }
    let hour = u16::from(bytes[11] - b'0') * 10 + u16::from(bytes[12] - b'0');
    let minute = u16::from(bytes[14] - b'0') * 10 + u16::from(bytes[15] - b'0');
    let year = u16::from(bytes[0] - b'0') * 1_000
        + u16::from(bytes[1] - b'0') * 100
        + u16::from(bytes[2] - b'0') * 10
        + u16::from(bytes[3] - b'0');
    let month = u16::from(bytes[5] - b'0') * 10 + u16::from(bytes[6] - b'0');
    let day = u16::from(bytes[8] - b'0') * 10 + u16::from(bytes[9] - b'0');
    if hour > 23 || minute > 59 || !is_valid_gregorian_date(year, month, day) {
        return None;
    }
    let mut date = [0; 10];
    date.copy_from_slice(&bytes[..10]);
    Some((date, hour * 60 + minute))
}

const fn is_valid_gregorian_date(year: u16, month: u16, day: u16) -> bool {
    let leap_year =
        year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap_year => 29,
        2 => 28,
        _ => return false,
    };
    day >= 1 && day <= days_in_month
}

fn validate_ygdk_photo_file_name(file_name: &str) -> Result<()> {
    let character_count = file_name.chars().count();
    if matches!(file_name, "." | "..")
        || !(1..=128).contains(&character_count)
        || file_name.trim() != file_name
        || file_name
            .chars()
            .any(|character| character.is_control() || matches!(character, '/' | '\\' | '"'))
    {
        return Err(invalid_input("打卡照片文件名无效"));
    }
    Ok(())
}

pub(crate) fn internal_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

#[cfg(test)]
mod tests {
    use std::io::Read;
    use std::time::{SystemTime, UNIX_EPOCH};

    use serde_json::json;
    use ubaa_core::facade::ErrorCode;

    use super::{
        MAX_YGDK_PHOTO_BYTES, build_ygdk_request, open_validated_ygdk_photo, parse_cgyy_request,
        read_ygdk_photo_after_initial_check, read_ygdk_photo_bytes, validate_ygdk_photo_file_name,
        validate_ygdk_time_shape, ygdk_photo_mime_type,
    };

    #[derive(Default)]
    struct CountingReader {
        bytes_read: u64,
    }

    impl Read for CountingReader {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            buffer.fill(1);
            self.bytes_read += buffer.len() as u64;
            Ok(buffer.len())
        }
    }

    fn 场馆预约请求_json() -> serde_json::Value {
        json!({
            "venueSiteId": 4,
            "reservationDate": "2026-03-29",
            "selections": [{"spaceId": 6, "timeId": 242}],
            "phone": "010-00000000",
            "theme": "test reservation",
            "purposeType": 1,
            "joinerNum": 1,
            "activityContent": "test content",
            "joiners": "tester",
            "isPhilosophySocialSciences": false,
            "isOffSchoolJoiner": false
        })
    }

    #[test]
    fn 场馆预约请求可以省略由_core_内部获取的验证码材料() {
        let input = 场馆预约请求_json().to_string();

        let request = parse_cgyy_request(&input).unwrap();

        assert!(!request.has_captcha_material());
    }

    #[test]
    fn 场馆预约请求拒绝所有已知私有验证码字段且不回显字段值() {
        for field in super::CGYY_PRIVATE_CAPTCHA_FIELDS {
            let mut value = 场馆预约请求_json();
            value[field] = "PRIVATE-CAPTCHA-VALUE".into();

            let error = parse_cgyy_request(&value.to_string()).unwrap_err();

            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(
                error.message,
                "场馆预约请求不得包含由 Core 内部管理的验证码字段"
            );
            assert!(!error.message.contains(field));
            assert!(!error.message.contains("PRIVATE-CAPTCHA-VALUE"));
        }
    }

    #[test]
    fn 场馆预约请求继续忽略普通未知字段以保持向前兼容() {
        let mut value = 场馆预约请求_json();
        value["futureCompatibleField"] = json!({"enabled": true});

        let request = parse_cgyy_request(&value.to_string()).unwrap();

        assert_eq!(request.venue_site_id, 4);
        assert!(!request.has_captcha_material());
    }

    #[test]
    fn 阳光打卡照片文件名拒绝当前与父目录别名() {
        for file_name in [".", ".."] {
            let error = validate_ygdk_photo_file_name(file_name).unwrap_err();
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, "打卡照片文件名无效");
            assert!(!error.message.contains(file_name));
        }
    }

    #[test]
    fn 阳光打卡危险文件名拒绝不依赖宿主文件系统() {
        for file_name in [
            "quote\"name.jpg",
            "line\r\nbreak.jpg",
            "back\\slash.jpg",
            "forward/slash.jpg",
            "control\u{0085}name.jpg",
            "trailing.jpg ",
            " leading.jpg",
            "",
        ] {
            let error =
                validate_ygdk_photo_file_name(file_name).expect_err("危险文件名必须由输入策略拒绝");
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, "打卡照片文件名无效");
        }
        validate_ygdk_photo_file_name("正常照片.JPG").expect("安全文件名应被接受");
    }

    #[test]
    fn 阳光打卡时间拒绝非法公历日期且先于照片读取() {
        for (start_time, end_time) in [
            ("2026-00-01 08:00", "2026-00-01 09:00"),
            ("2026-13-01 08:00", "2026-13-01 09:00"),
            ("2026-01-00 08:00", "2026-01-00 09:00"),
            ("2026-02-29 08:00", "2026-02-29 09:00"),
            ("2024-02-30 08:00", "2024-02-30 09:00"),
            ("2026-04-31 08:00", "2026-04-31 09:00"),
        ] {
            let error = validate_ygdk_time_shape(start_time, end_time)
                .expect_err("非法公历日期必须失败关闭");
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, "阳光打卡时间必须使用 yyyy-MM-dd HH:mm 格式");
            assert!(!error.message.contains(start_time));
            assert!(!error.message.contains(end_time));
        }
        validate_ygdk_time_shape("2024-02-29 08:00", "2024-02-29 09:00").expect("公历闰日应有效");

        let missing_photo = std::env::temp_dir().join("ubaa-cli-ygdk-must-not-read-private.jpg");
        let error = build_ygdk_request(
            11,
            22,
            "2026-02-29 08:00".into(),
            "2026-02-29 09:00".into(),
            None,
            &missing_photo,
            false,
        )
        .expect_err("非法日期必须在照片读取前失败");
        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert_eq!(error.message, "阳光打卡时间必须使用 yyyy-MM-dd HH:mm 格式");
        assert!(!error.message.contains("private"));
    }

    #[test]
    fn 阳光打卡照片安全扩展生成规范化图片_mime() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("系统时间应晚于 Unix epoch")
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "ubaa-cli-ygdk-photo-mime-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).expect("创建隔离照片目录");
        let photo = directory.join("safe-photo.AVIF");
        std::fs::write(&photo, b"safe-photo").expect("写入照片测试文件");

        let result = build_ygdk_request(
            11,
            22,
            "2026-04-01 08:00".into(),
            "2026-04-01 09:00".into(),
            None,
            &photo,
            false,
        );

        let _ = std::fs::remove_dir_all(&directory);
        let request = result.expect("安全 ASCII token 扩展应被规范化为 image subtype");
        assert_eq!(request.photo.mime_type, "image/avif");

        for invalid_extension in [
            "",
            "jpg;size=1",
            "svg/xml",
            "bad extension",
            "照片",
            "jpg\r\n",
        ] {
            let error =
                ygdk_photo_mime_type(invalid_extension).expect_err("危险图片 subtype 必须失败关闭");
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, "打卡照片扩展名无效");
            if !matches!(invalid_extension, "" | "照片") {
                assert!(!error.message.contains(invalid_extension));
            }
        }
    }

    #[test]
    fn 阳光打卡照片初检后路径替换必须失败关闭() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("系统时间应晚于 Unix epoch")
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "ubaa-cli-ygdk-photo-swap-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).expect("创建隔离照片目录");
        let selected = directory.join("selected.jpg");
        let replacement = directory.join("replacement.jpg");
        let retired = directory.join("retired.jpg");
        std::fs::write(&selected, b"selected-photo").expect("写入初检照片");
        std::fs::write(&replacement, b"replacement-private-photo").expect("写入替换照片");
        let selected_photo = open_validated_ygdk_photo(&selected).expect("初检照片有效");

        let result = read_ygdk_photo_after_initial_check(&selected, &selected_photo, || {
            std::fs::rename(&selected, &retired).expect("移走初检路径并保留文件句柄");
            std::fs::rename(&replacement, &selected).expect("替换初检路径");
        });

        drop(selected_photo);
        let _ = std::fs::remove_dir_all(&directory);
        let error = result.expect_err("初检后替换路径必须失败关闭");
        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert_eq!(error.message, "打卡照片在读取期间发生变化");
        assert!(!error.message.contains("selected"));
        assert!(!error.message.contains("replacement"));
    }

    #[test]
    fn 阳光打卡照片同尺寸路径替换也不能冒充原文件() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("系统时间应晚于 Unix epoch")
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "ubaa-cli-ygdk-same-size-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).expect("创建隔离照片目录");
        let selected = directory.join("selected.jpg");
        let replacement = directory.join("replacement.jpg");
        let retired = directory.join("retired.jpg");
        std::fs::write(&selected, b"original").expect("写入初检照片");
        std::fs::write(&replacement, b"replaced").expect("写入同尺寸替换照片");
        let selected_photo = open_validated_ygdk_photo(&selected).expect("初检照片有效");

        let result = read_ygdk_photo_after_initial_check(&selected, &selected_photo, || {
            std::fs::rename(&selected, &retired).expect("移走初检路径并保留文件句柄");
            std::fs::rename(&replacement, &selected).expect("替换为同尺寸文件");
        });

        drop(selected_photo);
        let _ = std::fs::remove_dir_all(&directory);
        let error = result.expect_err("文件大小相同不能替代身份检查");
        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert_eq!(error.message, "打卡照片在读取期间发生变化");
        assert!(!error.message.contains("selected"));
        assert!(!error.message.contains("replacement"));
    }

    #[test]
    fn 阳光打卡照片读取恰好限制到十_mib_加一字节() {
        let mut reader = CountingReader::default();

        let error = read_ygdk_photo_bytes(&mut reader).expect_err("超限照片必须失败关闭");

        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert_eq!(error.message, "打卡照片大小必须在 1 字节到 10 MiB 之间");
        assert_eq!(reader.bytes_read, MAX_YGDK_PHOTO_BYTES + 1);
    }
}
