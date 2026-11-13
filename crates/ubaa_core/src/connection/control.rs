//! 换网通知独立于业务锁，只撤销可重放读取，不触及学校写入。
use super::{CachingGatewayProbe, GatewayProbe, NetworkState};
use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::facade::operation_control;
use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};

#[derive(Clone, Copy)]
struct Observation {
    revision: u64,
    reads: [u64; 2],
    online: bool,
    deadline: Option<Instant>,
}

/// 不需要取得业务客户端锁的网络观察与读取取消入口。
#[derive(Clone)]
pub struct ClientNetworkControl {
    probe: Arc<CachingGatewayProbe<Box<dyn GatewayProbe>>>,
    state: Arc<tokio::sync::watch::Sender<Observation>>,
}

/// 一次换网的固定期限和修订；旧任务不能结束新任务。
#[derive(Clone)]
pub struct ClientNetworkChange {
    owner: ClientNetworkControl,
    revision: u64,
}

impl ClientNetworkControl {
    pub(crate) fn changing(&self) -> bool {
        self.state.borrow().deadline.is_some()
    }
    pub(crate) fn new(probe: Arc<CachingGatewayProbe<Box<dyn GatewayProbe>>>) -> Self {
        let (state, _) = tokio::sync::watch::channel(Observation {
            revision: 0,
            reads: [0, 0],
            online: true,
            deadline: None,
        });
        Self {
            probe,
            state: Arc::new(state),
        }
    }

    /// 立即撤销旧网络观察；离线取消两路读取，联网变化先取消直连读取。
    /// # Errors
    /// 超过两分钟的恢复预算被拒绝。
    pub fn begin_change(&self, online: bool, budget: Duration) -> Result<ClientNetworkChange> {
        if budget > Duration::from_secs(120) {
            return Err(UbaaError::invalid_input("换网恢复期限不能超过两分钟"));
        }
        self.probe.invalidate();
        let mut revision = 0;
        self.state.send_modify(|state| {
            state.revision += 1;
            revision = state.revision;
            state.online = online;
            state.deadline = Some(Instant::now() + budget);
            state.reads[0] += 1;
            if !online {
                state.reads[1] += 1;
            }
        });
        Ok(ClientNetworkChange {
            owner: self.clone(),
            revision,
        })
    }

    /// 手动切换撤销两路读取；认证和已发送写入继续使用各自控制范围。
    pub fn cancel_reads(&self) {
        self.state.send_modify(|state| {
            state.reads[0] += 1;
            state.reads[1] += 1;
        });
    }

    /// 在当前路线和换网期限内执行可重放读取，不能用于业务写入。
    /// # Errors
    /// 网络变化、离线或期限到达时取消 Future，并保留业务原错误。
    pub async fn run_read<T>(
        &self,
        route: ConnectionMode,
        fast_connect: bool,
        work: impl Future<Output = Result<T>>,
    ) -> Result<T> {
        let observation = *self.state.borrow();
        let scope = ReadScope {
            owner: self.clone(),
            route: usize::from(route == ConnectionMode::WebVpn),
            observation,
        };
        scope.check()?;
        let previous = operation_control::current();
        let checked = scope.clone();
        operation_control::with_operation_control(
            move || {
                if let Some(check) = &previous {
                    check()?;
                }
                checked.check()
            },
            operation_control::with_fast_connect(fast_connect, async {
                tokio::select! {
                    biased;
                    error = scope.interrupted() => Err(error),
                    result = work => { scope.check()?; result },
                }
            }),
        )
        .await
    }
}

impl ClientNetworkChange {
    /// 独立工作线程完成短探测，调用期间不占用业务读写锁。
    pub async fn inspect(&self) -> NetworkState {
        if !self.owner.state.borrow().online {
            return NetworkState::Unknown;
        }
        let probe = self.owner.probe.clone();
        let network = tokio::task::spawn_blocking(move || probe.probe(Duration::from_millis(500)))
            .await
            .unwrap_or(NetworkState::Unknown);
        if network != NetworkState::Campus {
            self.owner.state.send_modify(|state| {
                if state.revision == self.revision {
                    state.reads[1] += 1;
                }
            });
        }
        network
    }

    /// 收尾只解除本次期限，不恢复被取消的请求。
    pub fn finish(&self) {
        self.owner.state.send_modify(|state| {
            if state.revision == self.revision {
                state.deadline = None;
                state.revision += 1;
            }
        });
    }

    /// 到期或退出时取消本次仍在执行的读取，不影响后来的换网任务。
    pub fn cancel(&self) {
        self.owner.state.send_modify(|state| {
            if state.revision == self.revision {
                state.reads[0] += 1;
                state.reads[1] += 1;
                state.deadline = None;
                state.revision += 1;
            }
        });
    }
}

#[derive(Clone)]
struct ReadScope {
    owner: ClientNetworkControl,
    route: usize,
    observation: Observation,
}
impl ReadScope {
    fn check(&self) -> Result<()> {
        let current = self.owner.state.borrow();
        if !current.online || current.reads[self.route] != self.observation.reads[self.route] {
            return Err(UbaaError::network_changed());
        }
        if self
            .observation
            .deadline
            .is_some_and(|deadline| Instant::now() >= deadline)
        {
            return Err(UbaaError::new(
                ErrorCode::Timeout,
                ErrorKind::Network,
                false,
                "换网恢复期限已到",
            ));
        }
        Ok(())
    }

    async fn interrupted(&self) -> UbaaError {
        let mut updates = self.owner.state.subscribe();
        loop {
            if let Err(error) = self.check() {
                return error;
            }
            if let Some(deadline) = self.observation.deadline {
                tokio::select! {
                    _ = updates.changed() => {},
                    () = tokio::time::sleep_until(deadline.into()) => {},
                }
            } else {
                let _ = updates.changed().await;
            }
        }
    }
}

#[cfg(test)]
#[path = "control_tests.rs"]
mod tests;
