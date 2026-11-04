use super::CommandControl;
use std::{
    collections::VecDeque,
    io::{self, Write},
    sync::{Arc, Condvar, Mutex},
    time::Duration,
};
const CHUNK: usize = 64 * 1024;
const CAPACITY: usize = 4;
#[cfg(test)]
#[test]
fn 长中文输出块保留完整_utf8_字符() {
    let (mut writer, mut reader) = bounded_output(CommandControl::default());
    let bytes = "日".repeat(22000).into_bytes();
    let expected = bytes.clone();
    let producer = std::thread::spawn(move || {
        writer.write_all(&bytes).unwrap();
        writer.flush().unwrap();
    });
    let mut received = Vec::new();
    let mut valid = true;
    while let Some(chunk) = reader.read().unwrap() {
        valid &= std::str::from_utf8(&chunk.bytes).is_ok();
        received.extend(chunk.bytes);
        reader.acknowledge();
    }
    producer.join().unwrap();
    assert_eq!(received, expected);
    assert!(valid, "每块都必须可直接写入 Unicode 控制台");
}
#[derive(PartialEq)]
enum ProducerState {
    Open,
    Closed,
}
struct State {
    chunks: VecDeque<Vec<u8>>,
    in_flight: bool,
    failed: bool,
    producer: ProducerState,
    published: bool,
    cleanup: Option<CommandControl>,
    read_grace: Option<CommandControl>,
}
struct Shared {
    state: Mutex<State>,
    changed: Condvar,
    control: CommandControl,
    scope: Mutex<Option<ubaa_core::facade::SharedAccountGuard>>,
}
/// 每次只允许一个尚未确认的块，块上限 64 KiB。
pub struct OutputChunk {
    pub bytes: Vec<u8>,
}
pub struct OutputWriter(Arc<Shared>);
pub struct OutputReader(Arc<Shared>);
/// 传输内存最多四个 64 KiB 块（包含在途块）。不会缓存完整命令输出。
#[must_use]
pub fn bounded_output(control: CommandControl) -> (OutputWriter, OutputReader) {
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            chunks: VecDeque::new(),
            in_flight: false,
            failed: false,
            producer: ProducerState::Open,
            published: false,
            cleanup: None,
            read_grace: None,
        }),
        scope: Mutex::new(None),
        changed: Condvar::new(),
        control,
    });
    (OutputWriter(shared.clone()), OutputReader(shared))
}
impl Shared {
    fn check_scope(&self) -> io::Result<()> {
        if let Some(scope) = self.scope.lock().map_err(|_| failure())?.as_ref() {
            scope.check().map_err(|_| failure())?;
        }
        Ok(())
    }
}
fn failure() -> io::Error {
    io::Error::other("输出已停止或消费端已断开")
}
impl Write for OutputWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.check_scope()?;
        let mut state = self.0.state.lock().map_err(|_| failure())?;
        while state.chunks.len() + usize::from(state.in_flight) >= CAPACITY && !state.failed {
            state
                .cleanup
                .as_ref()
                .unwrap_or(&self.0.control)
                .check()
                .map_err(|_| failure())?;
            state = self
                .0
                .changed
                .wait_timeout(state, Duration::from_millis(10))
                .map_err(|_| failure())?
                .0;
        }
        if state.failed {
            return Err(failure());
        }
        state
            .cleanup
            .as_ref()
            .unwrap_or(&self.0.control)
            .check()
            .map_err(|_| failure())?;
        let limit = bytes.len().min(CHUNK);
        let count = match std::str::from_utf8(&bytes[..limit]) {
            Err(error) if error.error_len().is_none() && error.valid_up_to() > 0 => {
                error.valid_up_to()
            }
            _ => limit,
        };
        self.0.check_scope()?;
        if count > 0 {
            state.published = true;
            state.chunks.push_back(bytes[..count].to_vec());
            self.0.changed.notify_all();
        }
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        let mut state = self.0.state.lock().map_err(|_| failure())?;
        while (!state.chunks.is_empty() || state.in_flight) && !state.failed {
            state
                .cleanup
                .as_ref()
                .unwrap_or(&self.0.control)
                .check()
                .map_err(|_| failure())?;
            state = self
                .0
                .changed
                .wait_timeout(state, Duration::from_millis(10))
                .map_err(|_| failure())?
                .0;
        }
        state
            .cleanup
            .as_ref()
            .unwrap_or(&self.0.control)
            .check()
            .map_err(|_| failure())?;
        if state.failed { Err(failure()) } else { Ok(()) }
    }
}
impl OutputWriter {
    /// 输出仍绑定本次执行的固定共享身份，排队后再次核对。
    /// # Panics
    /// 共享身份锁被其他线程的 panic 污染时终止。
    pub fn bind_shared_account(&mut self, scope: Option<ubaa_core::facade::SharedAccountGuard>) {
        *self.0.scope.lock().unwrap() = scope;
    }
    /// 只用于已停止命令的错误交付，沿用停止时刻后的两秒总收尾预算。
    /// # Errors
    /// 收尾期限已到达或输出通道已损坏时失败。
    pub fn allow_cleanup(&mut self) -> io::Result<()> {
        let cleanup = self.0.control.cleanup();
        self.begin_cleanup(&cleanup)
    }
}
impl Drop for OutputWriter {
    fn drop(&mut self) {
        if let Ok(mut state) = self.0.state.lock() {
            state.producer = ProducerState::Closed;
            self.0.changed.notify_all();
        }
    }
}
impl OutputReader {
    /// 拉取下一块。原生写入和刷新成功后必须 acknowledge，失败应 fail。
    /// # Errors
    /// 取消、到期、消费协议错误或输出故障。
    pub fn read(&mut self) -> io::Result<Option<OutputChunk>> {
        let mut state = self.0.state.lock().map_err(|_| failure())?;
        if state.in_flight {
            return Err(io::Error::other("前一输出块尚未确认"));
        }
        loop {
            if self.0.control.check().is_err() && state.cleanup.is_none() && !state.published {
                state
                    .read_grace
                    .get_or_insert_with(|| self.0.control.cleanup())
                    .check()
                    .map_err(|_| failure())?;
            } else {
                state
                    .cleanup
                    .as_ref()
                    .unwrap_or(&self.0.control)
                    .check()
                    .map_err(|_| failure())?;
            }
            if state.failed {
                return Err(failure());
            }
            self.0.check_scope()?;
            if let Some(bytes) = state.chunks.pop_front() {
                state.in_flight = true;
                return Ok(Some(OutputChunk { bytes }));
            }
            if state.producer == ProducerState::Closed {
                return Ok(None);
            }
            state = self
                .0
                .changed
                .wait_timeout(state, Duration::from_millis(10))
                .map_err(|_| failure())?
                .0;
        }
    }
    /// 确认本块已经写入并刷新到宿主标准流。
    pub fn acknowledge(&mut self) {
        if let Ok(mut state) = self.0.state.lock() {
            state.in_flight = false;
            self.0.changed.notify_all();
        }
    }
    pub fn fail(&mut self) {
        self.0.control.cancel();
        if let Ok(mut state) = self.0.state.lock() {
            state.failed = true;
            state.chunks.clear();
            self.0.changed.notify_all();
        }
    }
}
impl Drop for OutputReader {
    fn drop(&mut self) {
        let complete = self.0.state.lock().is_ok_and(|s| {
            s.producer == ProducerState::Closed && s.chunks.is_empty() && !s.in_flight && !s.failed
        });
        if !complete {
            self.fail();
        }
    }
}
impl OutputWriter {
    /// 尚未交付任何字节时，允许一次至多两秒的停止诊断交付。
    /// # Errors
    /// 已有输出或队列发生故障时禁止追加诊断。
    pub(crate) fn begin_cleanup(&mut self, cleanup: &CommandControl) -> io::Result<()> {
        let mut state = self.0.state.lock().map_err(|_| failure())?;
        if state.published || state.failed {
            return Err(failure());
        }
        if state.cleanup.is_none() {
            state.cleanup = Some(
                state
                    .read_grace
                    .as_ref()
                    .map_or_else(|| cleanup.clone(), |grace| grace.earlier(cleanup)),
            );
        }
        self.0.changed.notify_all();
        Ok(())
    }
}

#[cfg(test)]
#[test]
fn 已排队正文在消费者取得前仍核对固定共享代次() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/output_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    let scope = ubaa_core::facade::SharedAccountGuard::new(&root, 1).unwrap();
    let (mut writer, mut reader) = bounded_output(CommandControl::default());
    writer.bind_shared_account(Some(scope));
    writer.write_all(b"private-before-revocation").unwrap();
    std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
    assert!(
        reader.read().is_err(),
        "已经排队但尚未交付的旧正文必须被拒绝"
    );
    drop((writer, reader));
    std::fs::remove_dir_all(root).unwrap();
}
