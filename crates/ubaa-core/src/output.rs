//! Host-neutral JSON envelope used by the CLI contract.

use serde::Serialize;

use crate::domain::ConnectionMode;
use crate::error::UbaaError;

/// Current CLI JSON schema version.
pub const JSON_SCHEMA_VERSION: u32 = 1;

/// Version used by read-only feature command envelopes.
pub const READONLY_JSON_SCHEMA_VERSION: u32 = 2;

/// Connection metadata included in every JSON response when known.
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonMeta {
    /// Client connection mode.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connection_mode: Option<ConnectionMode>,
}

/// Schema-v2 metadata for feature and route-policy commands.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadonlyJsonMeta {
    /// User-selected route policy.
    pub route_policy: crate::domain::RoutePolicy,
    /// Concrete route resolved for this request.
    pub resolved_route: crate::domain::ConnectionMode,
    /// Stable feature name.
    pub feature: String,
}

/// Schema-v2 metadata for aggregate authentication commands.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonMeta {
    /// User route policy; authentication itself always prepares both routes.
    pub route_policy: crate::domain::RoutePolicy,
    /// Routes that are ready after the operation, in Direct then `WebVPN` order.
    pub resolved_routes: Vec<crate::domain::ConnectionMode>,
    /// Stable feature name, always `auth` for this envelope.
    pub feature: String,
}

/// Schema-v2 aggregate authentication envelope.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonEnvelope<T> {
    /// Contract version.
    pub schema_version: u32,
    /// Whether no further input is required and at least one route is ready.
    pub ok: bool,
    /// Aggregate route result, including partial success.
    pub data: T,
    /// Safe aggregate error when the operation is not successful.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<crate::domain::SafeError>,
    /// Aggregate route metadata.
    pub meta: AggregateJsonMeta,
}

/// Read-only command envelope. Authentication compatibility output remains v1.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadonlyJsonEnvelope<T> {
    /// Contract version.
    pub schema_version: u32,
    /// Whether the command succeeded.
    pub ok: bool,
    /// Parsed feature data.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    /// Safe error payload.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<UbaaError>,
    /// Route and feature diagnostics.
    pub meta: ReadonlyJsonMeta,
}

impl<T> ReadonlyJsonEnvelope<T> {
    /// Build a successful feature response.
    #[must_use]
    pub fn success(data: T, meta: ReadonlyJsonMeta) -> Self {
        Self {
            schema_version: READONLY_JSON_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
            meta,
        }
    }

    /// Build a failed feature response.
    #[must_use]
    pub fn failure(
        error: UbaaError,
        meta: ReadonlyJsonMeta,
    ) -> ReadonlyJsonEnvelope<serde_json::Value> {
        ReadonlyJsonEnvelope {
            schema_version: READONLY_JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
            meta,
        }
    }
}

/// Stable success or failure envelope.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonEnvelope<T> {
    /// Contract version.
    pub schema_version: u32,
    /// True only when `data` is present and no error occurred.
    pub ok: bool,
    /// Successful command payload.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    /// Safe error payload.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<UbaaError>,
    /// Response metadata.
    pub meta: JsonMeta,
}

impl<T> std::fmt::Debug for JsonEnvelope<T> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("JsonEnvelope")
            .field("schema_version", &self.schema_version)
            .field("ok", &self.ok)
            .field("data_present", &self.data.is_some())
            .field("error_present", &self.error.is_some())
            .field("meta", &self.meta)
            .finish()
    }
}

impl<T> JsonEnvelope<T> {
    /// Create a successful response.
    pub const fn success(data: T, mode: ConnectionMode) -> Self {
        Self {
            schema_version: JSON_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
            meta: JsonMeta {
                connection_mode: Some(mode),
            },
        }
    }

    /// Create a failed response.
    #[must_use]
    pub const fn failure(error: UbaaError, mode: Option<ConnectionMode>) -> Self {
        Self {
            schema_version: JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
            meta: JsonMeta {
                connection_mode: mode,
            },
        }
    }
}
