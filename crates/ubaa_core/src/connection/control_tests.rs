use super::*;
use futures_util::FutureExt;
use std::sync::atomic::{AtomicBool, Ordering};

struct Campus;
impl GatewayProbe for Campus {
    fn probe(&self, _: Duration) -> NetworkState {
        NetworkState::Campus
    }
}
fn control() -> ClientNetworkControl {
    ClientNetworkControl::new(Arc::new(CachingGatewayProbe::with_default_ttl(Box::new(
        Campus,
    ))))
}
struct Pending(Arc<AtomicBool>);
impl Drop for Pending {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

#[tokio::test]
async fn 换网丢弃直连读取的实际_future() {
    let control = control();
    let dropped = Arc::new(AtomicBool::new(false));
    let reading = control.run_read(ConnectionMode::Direct, false, async {
        let _pending = Pending(dropped.clone());
        std::future::pending::<Result<()>>().await
    });
    tokio::pin!(reading);
    assert!(reading.as_mut().now_or_never().is_none());
    let change = control.begin_change(true, Duration::from_secs(30)).unwrap();
    assert!(reading.await.unwrap_err().is_network_changed());
    assert!(dropped.load(Ordering::SeqCst));
    change.finish();
}

#[tokio::test]
async fn 回校园网保留正常网关读取而离线立即取消() {
    let control = control();
    let (release, pending) = tokio::sync::oneshot::channel();
    let reading = control.run_read(ConnectionMode::WebVpn, false, async {
        pending.await.unwrap();
        Ok(())
    });
    tokio::pin!(reading);
    assert!(reading.as_mut().now_or_never().is_none());
    let change = control.begin_change(true, Duration::from_secs(30)).unwrap();
    assert_eq!(change.inspect().await, NetworkState::Campus);
    assert!(reading.as_mut().now_or_never().is_none());
    release.send(()).unwrap();
    reading.await.unwrap();
    let offline = control
        .begin_change(false, Duration::from_secs(30))
        .unwrap();
    let error = control
        .run_read(ConnectionMode::WebVpn, false, async { Ok(()) })
        .await
        .unwrap_err();
    assert!(error.is_network_changed());
    offline.finish();
}

#[tokio::test]
async fn 旧换网任务不能取消新任务或解除新期限() {
    let control = control();
    let old = control.begin_change(true, Duration::from_secs(30)).unwrap();
    let current = control.begin_change(true, Duration::ZERO).unwrap();
    old.cancel();
    old.finish();
    let error = control
        .run_read(ConnectionMode::Direct, true, async { Ok(()) })
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::Timeout);
    assert!(!error.retryable);
    current.finish();
    control
        .run_read(ConnectionMode::Direct, true, async {
            assert!(operation_control::fast_connect());
            Ok(())
        })
        .await
        .unwrap();
    assert!(!operation_control::fast_connect());
}

#[tokio::test]
async fn 已结束的探测迟到不能取消之后的网关读取() {
    struct DelayedProbe {
        started: std::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
        release: std::sync::Mutex<std::sync::mpsc::Receiver<()>>,
    }
    impl GatewayProbe for DelayedProbe {
        fn probe(&self, _: Duration) -> NetworkState {
            self.started
                .lock()
                .unwrap()
                .take()
                .unwrap()
                .send(())
                .unwrap();
            self.release.lock().unwrap().recv().unwrap();
            NetworkState::OffCampus
        }
    }
    let (started, pending) = tokio::sync::oneshot::channel();
    let (release, waiting) = std::sync::mpsc::channel();
    let control = ClientNetworkControl::new(Arc::new(CachingGatewayProbe::with_default_ttl(
        Box::new(DelayedProbe {
            started: std::sync::Mutex::new(Some(started)),
            release: std::sync::Mutex::new(waiting),
        }) as Box<dyn GatewayProbe>,
    )));
    let change = control.begin_change(true, Duration::from_secs(30)).unwrap();
    let inspect = tokio::spawn({
        let change = change.clone();
        async move { change.inspect().await }
    });
    pending.await.unwrap();
    change.finish();
    let (complete, response) = tokio::sync::oneshot::channel();
    let reading = control.run_read(ConnectionMode::WebVpn, false, async {
        response.await.unwrap();
        Ok(())
    });
    tokio::pin!(reading);
    assert!(reading.as_mut().now_or_never().is_none());
    release.send(()).unwrap();
    assert_eq!(inspect.await.unwrap(), NetworkState::OffCampus);
    assert!(reading.as_mut().now_or_never().is_none());
    complete.send(()).unwrap();
    reading.await.unwrap();
}
