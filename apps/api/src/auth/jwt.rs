use chrono::{Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};
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
    pub exp: i64,
    pub iat: i64,
}

pub fn issue_token(
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
        iat: now.timestamp(),
        exp: (now + Duration::hours(72)).timestamp(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| ApiError::Internal(e.into()))
}

pub fn decode_token(secret: &str, token: &str) -> ApiResult<Claims> {
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| ApiError::Unauthorized("Invalid or expired token".into()))
}
