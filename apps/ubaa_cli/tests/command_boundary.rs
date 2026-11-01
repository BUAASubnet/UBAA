#[allow(dead_code)]
#[path = "cli_contract/common/mod.rs"]
mod common;
use clap::Parser;
use std::io::{self, Cursor, Write};
use ubaa_cli::{Cli, run_with_backend};

#[derive(Default)]
struct FlushFailure(Vec<u8>);
impl Write for FlushFailure {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let count = bytes.len().min(3);
        self.0.extend_from_slice(&bytes[..count]);
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        Err(io::Error::other("合成刷新失败"))
    }
}
#[tokio::test]
async fn success_requires_output_flush() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "user", "show"]).unwrap();
    let code = run_with_backend(
        cli,
        &mut common::FakeBackend::default(),
        &mut Cursor::new([]),
        &mut FlushFailure::default(),
        &mut Vec::new(),
    )
    .await;
    assert_eq!(code, 7, "输出未交付时必须失败");
}
#[tokio::test]
async fn cgyy_request_uses_injected_stdin() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "cgyy",
        "submit",
        "--request-stdin",
        "--confirm-write",
    ])
    .unwrap();
    let mut stdout = Vec::new();
    let code = run_with_backend(
        cli,
        &mut common::FakeBackend::default(),
        &mut Cursor::new(br#"{"captchaVerification":"synthetic"}"#),
        &mut stdout,
        &mut Vec::new(),
    )
    .await;
    assert_eq!(code, 2);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert!(
        value["error"]["message"]
            .as_str()
            .unwrap()
            .contains("不得包含"),
        "注入输入必须送到现有校验器：{value}"
    );
}

use std::time::{Duration, Instant};
use ubaa_cli::{
    AttemptOutcome, CommandClass, CommandControl, execute_attempt, execute_fixed_attempt,
    execute_local_attempt, parse, prepare_input,
};

fn prepared(argv: &[&str]) -> (ubaa_cli::PreparedCommand, CommandControl) {
    let control = CommandControl::default();
    (
        prepare_input(
            parse(argv.iter().copied()).unwrap(),
            &mut Cursor::new([]),
            &control,
        )
        .unwrap(),
        control,
    )
}
#[tokio::test]
async fn expired_attempt_is_discarded_before_only_success_is_rendered() {
    let (input, control) = prepared(&["ubaa", "--json", "schedule", "terms"]);
    let mut backend = common::FakeRoutedBackend {
        fail_schedule: true,
        ..Default::default()
    };
    let first = execute_attempt(&input, &mut backend, &control).await;
    assert!(matches!(first, AttemptOutcome::AuthExpired { .. }));
    drop(first);
    backend.fail_schedule = false;
    let second = execute_attempt(&input, &mut backend, &control).await;
    let mut stdout = Vec::new();
    assert_eq!(
        second
            .into_result()
            .render(&control, &mut stdout, &mut Vec::new()),
        0
    );
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["ok"], true);
    common::assert_cli_schema(&value);
}
#[test]
fn every_existing_write_operation_is_classified_before_execution() {
    let cases = [
        vec!["signin", "perform", "--course-id", "course"],
        vec!["libbook", "cancel", "--booking-id", "1"],
        vec![
            "libbook",
            "reserve",
            "--area-id",
            "a",
            "--seat-id",
            "s",
            "--day",
            "2026-11-01",
            "--segment",
            "1",
        ],
        vec!["bykc", "select", "--course-id", "1"],
        vec!["bykc", "deselect", "--course-id", "1"],
        vec!["bykc", "sign", "--course-id", "1", "--sign-type", "1"],
        vec!["cgyy", "submit"],
        vec!["cgyy", "cancel", "--id", "1"],
        vec![
            "ygdk",
            "submit",
            "--classify-id",
            "1",
            "--item-id",
            "1",
            "--start-time",
            "a",
            "--end-time",
            "b",
            "--photo",
            "合成图片.jpg",
        ],
        vec!["evaluation", "submit-pending"],
    ];
    for args in cases {
        let plan = parse(std::iter::once("ubaa").chain(args)).unwrap();
        assert_eq!(plan.requirements().class, CommandClass::SchoolWrite);
    }
    assert_eq!(
        parse(["ubaa", "agenda", "unsynced"])
            .unwrap()
            .requirements()
            .class,
        CommandClass::Local
    );
    assert_eq!(
        parse(["ubaa", "auth", "status"])
            .unwrap()
            .requirements()
            .class,
        CommandClass::ExplicitAuth
    );
}
#[tokio::test]
async fn online_and_local_stop_codes_preserve_v13() {
    for deadline in [false, true] {
        let (input, _) = prepared(&["ubaa", "--json", "user", "show"]);
        let control = CommandControl::new(
            Instant::now(),
            if deadline {
                Duration::ZERO
            } else {
                Duration::from_mins(2)
            },
        );
        if !deadline {
            control.cancel();
        }
        let result =
            execute_fixed_attempt(&input, &mut common::FakeBackend::default(), &control).await;
        let mut out = Vec::new();
        assert_eq!(
            result
                .into_result()
                .render(&control, &mut out, &mut Vec::new()),
            if deadline { 5 } else { 7 }
        );
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(
            value["error"]["code"],
            if deadline {
                "timeout"
            } else {
                "internal_error"
            }
        );
        common::assert_cli_schema(&value);
        let (input, _) = prepared(&["ubaa", "--json", "agenda", "unsynced"]);
        let result = execute_local_attempt(&input, std::path::Path::new("必须不访问"), &control);
        let mut out = Vec::new();
        assert_eq!(
            result
                .into_result()
                .render(&control, &mut out, &mut Vec::new()),
            7
        );
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["error"]["code"], "storage");
        common::assert_cli_schema(&value);
    }
}
#[test]
fn invalid_write_confirmation_does_not_consume_stdin() {
    struct NeverRead;
    impl io::Read for NeverRead {
        fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
            panic!("禁止读取")
        }
    }
    impl io::BufRead for NeverRead {
        fn fill_buf(&mut self) -> io::Result<&[u8]> {
            panic!("禁止读取")
        }
        fn consume(&mut self, _: usize) {
            panic!("禁止读取")
        }
    }
    let control = CommandControl::default();
    prepare_input(
        parse(["ubaa", "cgyy", "submit", "--request-stdin"]).unwrap(),
        &mut NeverRead,
        &control,
    )
    .unwrap();
}
#[test]
fn output_chunks_require_acknowledgement_and_clean_eof_retains_control() {
    use ubaa_cli::runtime::bounded_output;
    let control = CommandControl::default();
    let (mut writer, mut reader) = bounded_output(control.clone());
    let producer = std::thread::spawn(move || {
        writer.write_all(&vec![42; 300_000]).unwrap();
        writer.flush().unwrap();
    });
    let mut count = 0;
    while let Some(chunk) = reader.read().unwrap() {
        assert!(chunk.bytes.len() <= 64 * 1024);
        count += chunk.bytes.len();
        assert!(reader.read().is_err());
        reader.acknowledge();
    }
    producer.join().unwrap();
    drop(reader);
    assert_eq!(count, 300_000);
    assert!(control.check().is_ok());
}
#[test]
fn full_output_queue_wakes_on_cancellation_and_reader_failure() {
    use ubaa_cli::runtime::bounded_output;
    for cancel in [false, true] {
        let control = CommandControl::default();
        let (mut writer, mut reader) = bounded_output(control.clone());
        for _ in 0..4 {
            writer.write_all(&vec![1; 65536]).unwrap();
        }
        let (sent, received) = std::sync::mpsc::channel();
        let producer = std::thread::spawn(move || {
            sent.send(writer.write_all(&[2]).is_err()).unwrap();
        });
        assert!(received.try_recv().is_err());
        if cancel {
            control.cancel();
        } else {
            reader.fail();
        }
        assert!(received.recv_timeout(Duration::from_secs(1)).unwrap());
        producer.join().unwrap();
    }
}

#[tokio::test]
async fn stopped_result_can_deliver_one_bounded_timeout_envelope() {
    use ubaa_cli::runtime::bounded_output;
    let (input, _) = prepared(&["ubaa", "--json", "user", "show"]);
    let control = CommandControl::new(Instant::now(), Duration::ZERO);
    let result = execute_fixed_attempt(&input, &mut common::FakeBackend::default(), &control)
        .await
        .into_result();
    let (mut out, mut out_reader) = bounded_output(control.clone());
    let (mut err, mut err_reader) = bounded_output(control.clone());
    let collect_out = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        while let Some(chunk) = out_reader.read().unwrap() {
            bytes.extend(chunk.bytes);
            out_reader.acknowledge();
        }
        bytes
    });
    let collect_err = std::thread::spawn(move || {
        while err_reader.read().unwrap().is_some() {
            err_reader.acknowledge();
        }
    });
    let code = result.render_bounded(&control, &mut out, &mut err);
    drop((out, err));
    assert_eq!(code, 5);
    let value: serde_json::Value = serde_json::from_slice(&collect_out.join().unwrap()).unwrap();
    assert_eq!(value["error"]["code"], "timeout");
    common::assert_cli_schema(&value);
    collect_err.join().unwrap();
}

#[test]
fn login_snapshot_reads_required_lines_without_waiting_for_eof() {
    let control = CommandControl::default();
    let plan = parse([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--username",
        "synthetic",
        "--password-stdin",
    ])
    .unwrap();
    let mut input = Cursor::new(b"synthetic-password\nnext-command\n");
    prepare_input(plan, &mut input, &control).unwrap();
    assert_eq!(input.position(), 19);
}

#[test]
fn invalid_config_is_rejected_before_prompting_for_password() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_mode_h2_common_a/tests");
    std::fs::create_dir_all(&root).unwrap();
    let config = root.join(format!("invalid_config_{}", uuid::Uuid::new_v4()));
    std::fs::write(&config, "合成普通文件").unwrap();
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--config-dir")
        .arg(&config)
        .args(["auth", "login", "--username", "synthetic-input-order"])
        .stdin(std::process::Stdio::null())
        .output()
        .unwrap();
    std::fs::remove_file(config).unwrap();
    assert_eq!(output.status.code(), Some(7));
    assert!(output.stdout.is_empty());
    let error = String::from_utf8(output.stderr).unwrap();
    assert!(error.contains("本机日程账号无法安全撤销"), "{error}");
    assert!(!error.contains("密码"), "{error}");
}
