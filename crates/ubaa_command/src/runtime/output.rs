use super::CommandControl;
use std::{
    collections::VecDeque,
    io::{self, Write},
    sync::{Arc, Condvar, Mutex},
    time::Duration,
};
const CHUNK: usize = 64 * 1024;
const CAPACITY: usize = 4;
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
        changed: Condvar::new(),
        control,
    });
    (OutputWriter(shared.clone()), OutputReader(shared))
}
fn failure() -> io::Error {
    io::Error::other("输出已停止或消费端已断开")
}
impl Write for OutputWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
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
        let count = bytes.len().min(CHUNK);
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
