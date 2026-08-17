//! Host-neutral JSON envelope used by the CLI contract.

use serde::Serialize;

use crate::domain::ConnectionMode;
use crate::error::UbaaError;

/// Current CLI JSON schema version.
pub const JSON_SCHEMA_VERSION: u32 = 1;

/// Connection metadata included in every JSON response when known.
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JsonMeta {
    /// Client connection mode.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connection_mode: Option<ConnectionMode>,
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
