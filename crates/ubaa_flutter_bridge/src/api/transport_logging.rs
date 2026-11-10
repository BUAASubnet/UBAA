//! Flutter Bridge 的默认安全诊断日志接线。

use tracing::{Level, Metadata, Subscriber};
use tracing_subscriber::filter::filter_fn;
use tracing_subscriber::prelude::*;

const TRANSPORT_TARGET: &str = "ubaa::transport";
const SCHOOL_GATE_TARGET: &str = "ubaa::app_service::school_gate";
const SAFE_FIELDS: [&str; 4] = ["message", "stage", "reason", "elapsed_ms"];

pub(super) fn install_default() {
    let subscriber = default_subscriber();
    let _ = tracing::subscriber::set_global_default(subscriber);
}

fn default_subscriber() -> impl Subscriber + Send + Sync {
    tracing_subscriber::registry().with(
        tracing_subscriber::fmt::layer()
            .without_time()
            .with_ansi(false)
            .with_target(false)
            .with_writer(std::io::stderr)
            .with_filter(filter_fn(is_safe_diagnostic_event)),
    )
}

fn is_safe_diagnostic_event(metadata: &Metadata<'_>) -> bool {
    let fields = metadata.fields();
    match metadata.target() {
        TRANSPORT_TARGET => {
            metadata.level() == &Level::DEBUG
                && fields.iter().count() == SAFE_FIELDS.len()
                && SAFE_FIELDS.iter().all(|name| fields.field(name).is_some())
        }
        SCHOOL_GATE_TARGET => {
            metadata.is_event()
                && metadata.level() == &Level::WARN
                && fields.iter().count() == 1
                && fields.field("message").is_some()
        }
        _ => false,
    }
}
