//! Reqwest 生产传输的私有安全诊断。

use std::error::Error as StdError;
use std::io;
use std::time::Duration;

const MAX_ERROR_CHAIN_DEPTH: usize = 8;

#[derive(Clone, Copy)]
pub(super) enum TransportStage {
    Send,
    Receive,
}

impl TransportStage {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Send => "send",
            Self::Receive => "receive",
        }
    }
}

#[derive(Clone, Copy)]
pub(super) enum FailureReason {
    Timeout,
    ConnectionRefused,
    ConnectionReset,
    ConnectionAborted,
    NotConnected,
    BrokenPipe,
    UnexpectedEof,
    AddressUnavailable,
    Builder,
    Redirect,
    Status,
    Connect,
    Request,
    Body,
    Decode,
    ResponseTooLarge,
    Unknown,
}

impl FailureReason {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Timeout => "timeout",
            Self::ConnectionRefused => "connection_refused",
            Self::ConnectionReset => "connection_reset",
            Self::ConnectionAborted => "connection_aborted",
            Self::NotConnected => "not_connected",
            Self::BrokenPipe => "broken_pipe",
            Self::UnexpectedEof => "unexpected_eof",
            Self::AddressUnavailable => "address_unavailable",
            Self::Builder => "builder",
            Self::Redirect => "redirect",
            Self::Status => "status",
            Self::Connect => "connect",
            Self::Request => "request",
            Self::Body => "body",
            Self::Decode => "decode",
            Self::ResponseTooLarge => "response_too_large",
            Self::Unknown => "unknown",
        }
    }
}

pub(super) fn record_reqwest_failure(
    stage: TransportStage,
    error: &reqwest::Error,
    elapsed: Duration,
) {
    record_known_failure(stage, classify(error), elapsed);
}

pub(super) fn record_known_failure(
    stage: TransportStage,
    reason: FailureReason,
    elapsed: Duration,
) {
    tracing::debug!(
        target: "ubaa::transport",
        stage = stage.as_str(),
        reason = reason.as_str(),
        elapsed_ms = saturated_millis(elapsed),
        "HTTP 传输失败"
    );
}

fn classify(error: &reqwest::Error) -> FailureReason {
    if error.is_timeout() {
        return FailureReason::Timeout;
    }
    if let Some(reason) = io_reason(error) {
        return reason;
    }
    if error.is_builder() {
        FailureReason::Builder
    } else if error.is_redirect() {
        FailureReason::Redirect
    } else if error.is_status() {
        FailureReason::Status
    } else if error.is_connect() {
        FailureReason::Connect
    } else if error.is_request() {
        FailureReason::Request
    } else if error.is_body() {
        FailureReason::Body
    } else if error.is_decode() {
        FailureReason::Decode
    } else {
        FailureReason::Unknown
    }
}

fn io_reason(error: &reqwest::Error) -> Option<FailureReason> {
    let mut current: Option<&(dyn StdError + 'static)> = Some(error);
    for _ in 0..MAX_ERROR_CHAIN_DEPTH {
        let source = current?;
        if let Some(error) = source.downcast_ref::<io::Error>() {
            return match error.kind() {
                io::ErrorKind::TimedOut => Some(FailureReason::Timeout),
                io::ErrorKind::ConnectionRefused => Some(FailureReason::ConnectionRefused),
                io::ErrorKind::ConnectionReset => Some(FailureReason::ConnectionReset),
                io::ErrorKind::ConnectionAborted => Some(FailureReason::ConnectionAborted),
                io::ErrorKind::NotConnected => Some(FailureReason::NotConnected),
                io::ErrorKind::BrokenPipe => Some(FailureReason::BrokenPipe),
                io::ErrorKind::UnexpectedEof => Some(FailureReason::UnexpectedEof),
                io::ErrorKind::AddrNotAvailable => Some(FailureReason::AddressUnavailable),
                _ => None,
            };
        }
        current = source.source();
    }
    None
}

fn saturated_millis(elapsed: Duration) -> u64 {
    u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX)
}
