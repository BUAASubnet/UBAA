//! Stable domain values shared by the core facade and host bindings.

use std::fmt;

use serde::{Deserialize, Serialize, Serializer};

/// Network path used for all requests owned by a client.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionMode {
    /// Reach upstream services directly.
    Direct,
    /// Route upstream services through the BUAA `WebVPN` gateway.
    WebVpn,
}

/// A value that redacts its contents in all ordinary formatting and serialization.
#[derive(Clone, Eq, PartialEq)]
pub struct SecretValue(String);

impl SecretValue {
    /// Wrap a secret without exposing it through formatting traits.
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// Explicitly borrow the secret for the narrow scope of an upstream request.
    #[must_use]
    pub fn expose_secret(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretValue([REDACTED])")
    }
}

impl fmt::Display for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("[REDACTED]")
    }
}

impl Serialize for SecretValue {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str("[REDACTED]")
    }
}

/// Credentials and optional captcha answer for one login submission.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginInput {
    /// SSO account name.
    pub username: String,
    /// SSO password, always redacted outside the request boundary.
    pub password: SecretValue,
    /// Captcha text supplied by the user when challenged.
    pub captcha: Option<String>,
}

/// Captcha state tied to the current in-memory login flow.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginChallenge {
    /// Upstream captcha identifier.
    pub id: String,
    /// CAS execution token associated with the challenge.
    pub execution: String,
    /// Ephemeral image data for interactive hosts; never persisted.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_data_url: Option<String>,
}

/// User Center profile mapped from the legacy `UserInfo` DTO.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProfile {
    /// Identity-document type code.
    pub id_card_type: Option<String>,
    /// Human-readable identity-document type.
    pub id_card_type_name: Option<String>,
    /// Phone value as returned by User Center.
    pub phone: Option<String>,
    /// School identifier. The upstream field is spelled `schoolid`.
    #[serde(alias = "schoolid")]
    pub school_id: Option<String>,
    /// Display name.
    pub name: Option<String>,
    /// Identity-document number.
    pub id_card_number: Option<String>,
    /// Email address.
    pub email: Option<String>,
    /// User Center account name.
    pub username: Option<String>,
}

/// User Center JSON wrapper used by both status and profile endpoints.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct UserInfoResponse {
    /// Upstream result code; zero denotes success in the frozen implementation.
    pub code: i64,
    /// Optional profile payload.
    pub data: Option<UserProfile>,
}
