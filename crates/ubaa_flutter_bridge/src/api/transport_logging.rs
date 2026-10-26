//! Flutter Bridge 的默认安全传输日志接线。

use tracing::{Level, Metadata, Subscriber};
use tracing_subscriber::filter::filter_fn;
use tracing_subscriber::prelude::*;

const TRANSPORT_TARGET: &str = "ubaa::transport";
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
            .with_filter(filter_fn(is_safe_transport_event)),
    )
}

fn is_safe_transport_event(metadata: &Metadata<'_>) -> bool {
    metadata.target() == TRANSPORT_TARGET
        && metadata.level() == &Level::DEBUG
        && metadata.fields().iter().count() == SAFE_FIELDS.len()
        && SAFE_FIELDS
            .iter()
            .all(|name| metadata.fields().field(name).is_some())
}
