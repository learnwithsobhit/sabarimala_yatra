use chrono::{Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::models::MemberRole;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: Uuid,
    pub member_id: Uuid,
    pub trip_id: Uuid,
    pub role: MemberRole,
    pub name: String,
    pub phone: String,
    /// "access" | "refresh" — refresh JWTs are not accepted by AuthUserExt
    #[serde(default = "default_token_type")]
    pub typ: String,
    pub exp: i64,
    pub iat: i64,
}

fn default_token_type() -> String {
    "access".into()
}

pub fn issue_access_token(
    secret: &str,
    user_id: Uuid,
    member_id: Uuid,
    trip_id: Uuid,
    role: MemberRole,
    name: String,
    phone: String,
) -> ApiResult<String> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        member_id,
        trip_id,
        role,
        name,
        phone,
        typ: "access".into(),
        iat: now.timestamp(),
        exp: (now + Duration::hours(2)).timestamp(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| ApiError::Internal(e.into()))
}

/// Opaque refresh token (random bytes) + SHA-256 hash for DB storage.
pub fn mint_refresh_token_pair() -> (String, String) {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let raw = hex::encode(bytes);
    let hash = hash_refresh_token(&raw);
    (raw, hash)
}

pub fn hash_refresh_token(raw: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(raw.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn decode_token(secret: &str, token: &str) -> ApiResult<Claims> {
    let claims = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| ApiError::Unauthorized("Invalid or expired token".into()))?;

    if claims.typ != "access" {
        return Err(ApiError::Unauthorized("Access token required".into()));
    }
    Ok(claims)
}

/// Backward-compatible alias used by older call sites.
pub fn issue_token(
    secret: &str,
    user_id: Uuid,
    member_id: Uuid,
    trip_id: Uuid,
    role: MemberRole,
    name: String,
    phone: String,
) -> ApiResult<String> {
    issue_access_token(secret, user_id, member_id, trip_id, role, name, phone)
}
