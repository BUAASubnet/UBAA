//! 双进程合成目录验证：持续持锁时启动必须有界失败，释放后可重试。
use std::io::{BufRead, Write};
use std::process::{Command, Stdio};
use std::time::Duration;
use ubaa_core::facade::{ErrorCode, UbaaClient};

#[test]
fn 合成持锁子进程() {
    let Ok(path) = std::env::var("UBAA_TEST_LOCK_DIRECTORY") else {
        return;
    };
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(std::path::Path::new(&path).join(".session.lock"))
        .unwrap();
    file.lock().unwrap();
    println!("已持锁");
    std::io::stdout().flush().unwrap();
    let mut release = String::new();
    std::io::stdin().read_line(&mut release).unwrap();
}

#[test]
fn 另一进程持续持锁时启动有界失败且解锁后恢复() {
    let root = std::env::temp_dir().join(format!("ubaa-lock-budget-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let _initial = UbaaClient::open(&root).unwrap();
    let mut holder = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "lock_budget::合成持锁子进程", "--nocapture"])
        .env("UBAA_TEST_LOCK_DIRECTORY", &root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut output = std::io::BufReader::new(holder.stdout.take().unwrap());
    loop {
        let mut line = String::new();
        assert_ne!(output.read_line(&mut line).unwrap(), 0);
        if line.contains("已持锁") {
            break;
        }
    }
    let (sender, receiver) = std::sync::mpsc::channel();
    let directory = root.clone();
    let waiter = std::thread::spawn(move || {
        sender
            .send(UbaaClient::open(directory).map(|_| ()))
            .unwrap();
    });
    let result = receiver.recv_timeout(Duration::from_secs(5));
    // 先释放并回收子进程，RED 也不留下持续持锁者。
    holder
        .stdin
        .take()
        .unwrap()
        .write_all(b"release\n")
        .unwrap();
    assert!(holder.wait().unwrap().success());
    waiter.join().unwrap();
    let error = result
        .expect("启动不能等待持锁进程无限释放")
        .expect_err("资源忙必须明确失败");
    assert_eq!(error.code, ErrorCode::Timeout);
    assert!(UbaaClient::open(&root).is_ok());
    std::fs::remove_dir_all(root).unwrap();
}
