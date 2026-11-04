use super::{Body, BridgeCommandResult};
use std::sync::{Arc, Mutex};
use ubaa_command::runtime::{OutputReader, bounded_output};

/// stdout/stderr 各保留至多四个 64 KiB 块，写入与刷新成功后逐块确认。
pub struct BridgeCommandDelivery {
    stdout: Arc<Mutex<OutputReader>>,
    stderr: Arc<Mutex<OutputReader>>,
    hints: Arc<Mutex<Vec<crate::api::write::command::CommandHint>>>,
    known: bool,
    completion: tokio::sync::Mutex<Option<tokio::task::JoinHandle<i32>>>,
}
impl BridgeCommandResult {
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    // FRB 需要在 Tokio worker 内启动输出任务。
    #[allow(clippy::unused_async)]
    pub async fn deliver(&self) -> BridgeCommandDelivery {
        let body = self.body.lock().unwrap().take();
        let known =
            matches!(body.as_ref(),Some(Body::Result(result)) if result.write_result_known());
        let hints = self.hints.clone();
        let control = self.control.clone();
        let scope = self.scope.clone();
        let (mut out, out_reader) = bounded_output(control.clone());
        let (mut err, err_reader) = bounded_output(control.clone());
        out.bind_shared_account(scope.clone());
        err.bind_shared_account(scope);
        let completion = tokio::task::spawn_blocking(move || {
            if control.check().is_err()
                && !matches!(body, Some(Body::Result(_)))
                && (out.allow_cleanup().is_err() || err.allow_cleanup().is_err())
            {
                return 7;
            }
            match body {
                Some(Body::Result(result)) => result.render_bounded(&control, &mut out, &mut err),
                Some(Body::Parse(error)) => error.render(&mut out, &mut err),
                Some(Body::Error {
                    json,
                    feature,
                    error,
                    resolution,
                }) => ubaa_command::render_operation_error(
                    json,
                    feature,
                    ubaa_core::facade::RoutedError { error, resolution },
                    &mut out,
                    &mut err,
                ),
                Some(Body::Agenda { json, result }) => {
                    result.render(json, &control, &mut out, &mut err)
                }
                Some(Body::LocalError {
                    json,
                    operation,
                    error,
                }) => command_error(json, &operation, error, &mut out, &mut err),
                None => 7,
            }
        });
        BridgeCommandDelivery {
            hints,
            known,
            stdout: Arc::new(Mutex::new(out_reader)),
            stderr: Arc::new(Mutex::new(err_reader)),
            completion: tokio::sync::Mutex::new(Some(completion)),
        }
    }
}
fn command_error(
    json: bool,
    operation: &str,
    error: ubaa_command::agenda::LocalError,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> i32 {
    ubaa_command::agenda::render_agenda_error(json, operation, error, stdout, stderr)
}
impl BridgeCommandDelivery {
    /// # Errors
    /// 输出已停止、共享身份失效或收尾任务失败时返回错误。
    pub async fn next_stdout(&self) -> Result<Option<Vec<u8>>, String> {
        read(self.stdout.clone()).await
    }
    /// # Errors
    /// 输出已停止、共享身份失效或收尾任务失败时返回错误。
    pub async fn next_stderr(&self) -> Result<Option<Vec<u8>>, String> {
        read(self.stderr.clone()).await
    }
    /// # Errors
    /// 输出锁不可用时返回错误。
    pub fn acknowledge_stdout(&self) -> Result<(), String> {
        self.stdout.lock().map_err(|_| failure())?.acknowledge();
        Ok(())
    }
    /// # Errors
    /// 输出锁不可用时返回错误。
    pub fn acknowledge_stderr(&self) -> Result<(), String> {
        self.stderr.lock().map_err(|_| failure())?.acknowledge();
        Ok(())
    }
    pub fn fail(&self) {
        if let Ok(mut out) = self.stdout.lock() {
            out.fail();
        }
        if let Ok(mut err) = self.stderr.lock() {
            err.fail();
        }
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub async fn finish(&self) -> i32 {
        let code = match self.completion.lock().await.take() {
            Some(task) => task.await.unwrap_or(7),
            None => 7,
        };
        if !matches!(code, 5 | 7) && self.known {
            let hints = std::mem::take(&mut *self.hints.lock().unwrap());
            let _ = tokio::task::spawn_blocking(move || {
                for (cache, id) in hints {
                    let _ = cache.dismiss_write_readback(&id);
                }
            })
            .await;
        }
        code
    }
}
fn failure() -> String {
    "命令输出已停止".into()
}
async fn read(reader: Arc<Mutex<OutputReader>>) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        reader
            .lock()
            .map_err(|_| failure())?
            .read()
            .map(|v| v.map(|c| c.bytes))
            .map_err(|_| failure())
    })
    .await
    .map_err(|_| failure())?
}
