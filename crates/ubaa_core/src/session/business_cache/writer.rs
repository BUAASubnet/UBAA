//! 单个缓存按提交顺序处理磁盘操作，读取结果无需等待文件锁或同步落盘。
use super::file::BusinessSessionFile;
use std::sync::{Arc, mpsc};
use std::thread::{self, JoinHandle};

type Job = Box<dyn FnOnce(&BusinessSessionFile) + Send>;

#[derive(Default)]
pub(super) struct Writer {
    sender: Option<mpsc::Sender<Job>>,
    thread: Option<JoinHandle<()>>,
}

impl Writer {
    pub(super) fn submit(
        &mut self,
        file: &Arc<BusinessSessionFile>,
        job: impl FnOnce(&BusinessSessionFile) + Send + 'static,
    ) -> bool {
        if self.sender.is_none() {
            let (sender, receiver) = mpsc::channel::<Job>();
            let file = Arc::clone(file);
            let Ok(thread) = thread::Builder::new()
                .name("ubaa-business-session".into())
                .spawn(move || {
                    for job in receiver {
                        job(&file);
                    }
                })
            else {
                return false;
            };
            self.sender = Some(sender);
            self.thread = Some(thread);
        }
        let dispatch = tracing::dispatcher::get_default(Clone::clone);
        self.sender.as_ref().is_some_and(|sender| {
            sender
                .send(Box::new(move |file| {
                    tracing::dispatcher::with_default(&dispatch, || job(file));
                }))
                .is_ok()
        })
    }

    pub(super) fn drain(&mut self) {
        self.sender.take();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for Writer {
    fn drop(&mut self) {
        self.drain();
    }
}
