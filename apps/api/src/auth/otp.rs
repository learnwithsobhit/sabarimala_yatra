use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use chrono::{Duration, Utc};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::jwt::issue_token;
use crate::config::Config;
use crate::error::{ApiError, ApiResult};
use crate::models::{MemberRole, TripMemberRow};

#[derive(Debug, Deserialize)]
pub struct OtpRequest {
    pub phone: String,
}

#[derive(Debug, Serialize)]
pub struct OtpRequestResponse {
    pub message: String,
    pub expires_in_seconds: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dev_hint: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct OtpVerify {
    pub phone: String,
    pub code: String,
    /// Optional: which trip to join session for (defaults to newest trip for this phone)
    pub trip_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub user: AuthProfile,
}

#[derive(Debug, Serialize)]
pub struct AuthProfile {
    pub user_id: Uuid,
    pub member_id: Uuid,
    pub trip_id: Uuid,
    pub role: MemberRole,
    pub display_name: String,
    pub phone: String,
}

fn normalize_phone(raw: &str) -> ApiResult<String> {
    let digits: String = raw.chars().filter(|c| c.is_ascii_digit() || *c == '+').collect();
    if digits.len() < 10 {
        return Err(ApiError::BadRequest("Phone number looks invalid".into()));
    }
    if digits.starts_with('+') {
        Ok(digits)
    } else if digits.len() == 10 {
        Ok(format!("+91{digits}"))
    } else {
        Ok(format!("+{digits}"))
    }
}

fn hash_code(code: &str) -> ApiResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(code.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| ApiError::Internal(anyhow::anyhow!("hash error: {e}")))
}

fn verify_code(code: &str, hash: &str) -> bool {
    PasswordHash::new(hash)
        .ok()
        .and_then(|parsed| Argon2::default().verify_password(code.as_bytes(), &parsed).ok())
        .is_some()
}

pub async fn request_otp(db: &PgPool, config: &Config, phone: &str) -> ApiResult<OtpRequestResponse> {
    let phone = normalize_phone(phone)?;

    let rostered: Option<(Uuid,)> =
        sqlx::query_as("SELECT id FROM users WHERE phone_e164 = $1")
            .bind(&phone)
            .fetch_optional(db)
            .await?;

    if rostered.is_none() {
        return Err(ApiError::Forbidden(
            "This phone is not on the trip roster. Ask the leader to add you.".into(),
        ));
    }

    let code = if config.dev_auth {
        config.dev_otp_code.clone()
    } else {
        format!("{:06}", rand::random::<u32>() % 1_000_000)
    };

    let hash = hash_code(&code)?;
    let expires = Utc::now() + Duration::minutes(10);

    sqlx::query(
        r#"INSERT INTO otp_challenges (phone_e164, code_hash, expires_at)
           VALUES ($1, $2, $3)"#,
    )
    .bind(&phone)
    .bind(&hash)
    .bind(expires)
    .execute(db)
    .await?;

    // Production: send SMS. Dev: return hint.
    Ok(OtpRequestResponse {
        message: "OTP sent if this number is rostered.".into(),
        expires_in_seconds: 600,
        dev_hint: config.dev_auth.then(|| format!("DEV OTP: {code}")),
    })
}

pub async fn verify_otp(
    db: &PgPool,
    config: &Config,
    phone: &str,
    code: &str,
    trip_id: Option<Uuid>,
) -> ApiResult<AuthResponse> {
    let phone = normalize_phone(phone)?;

    if config.dev_auth && code == config.dev_otp_code {
        // accept
    } else {
        let row: Option<(Uuid, String, chrono::DateTime<Utc>, Option<chrono::DateTime<Utc>>)> =
            sqlx::query_as(
                r#"SELECT id, code_hash, expires_at, consumed_at
                   FROM otp_challenges
                   WHERE phone_e164 = $1
                   ORDER BY created_at DESC
                   LIMIT 1"#,
            )
            .bind(&phone)
            .fetch_optional(db)
            .await?;

        let Some((id, hash, expires, consumed)) = row else {
            return Err(ApiError::Unauthorized("No OTP requested".into()));
        };
        if consumed.is_some() {
            return Err(ApiError::Unauthorized("OTP already used".into()));
        }
        if expires < Utc::now() {
            return Err(ApiError::Unauthorized("OTP expired".into()));
        }
        if !verify_code(code, &hash) {
            return Err(ApiError::Unauthorized("Incorrect OTP".into()));
        }
        sqlx::query("UPDATE otp_challenges SET consumed_at = NOW() WHERE id = $1")
            .bind(id)
            .execute(db)
            .await?;
    }

    let member: TripMemberRow = if let Some(tid) = trip_id {
        sqlx::query_as(
            r#"
            SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
                   u.display_name, u.phone_e164, tm.is_active
            FROM trip_members tm
            JOIN users u ON u.id = tm.user_id
            WHERE u.phone_e164 = $1 AND tm.trip_id = $2 AND tm.is_active
            "#,
        )
        .bind(&phone)
        .bind(tid)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| ApiError::NotFound("Not a member of this trip".into()))?
    } else {
        sqlx::query_as(
            r#"
            SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
                   u.display_name, u.phone_e164, tm.is_active
            FROM trip_members tm
            JOIN users u ON u.id = tm.user_id
            JOIN trips t ON t.id = tm.trip_id
            WHERE u.phone_e164 = $1 AND tm.is_active
            ORDER BY t.starts_on DESC
            LIMIT 1
            "#,
        )
        .bind(&phone)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| ApiError::NotFound("No active trip membership for this phone".into()))?
    };

    let token = issue_token(
        &config.jwt_secret,
        member.user_id,
        member.id,
        member.trip_id,
        member.role,
        member.display_name.clone(),
        member.phone_e164.clone(),
    )?;

    Ok(AuthResponse {
        access_token: token,
        user: AuthProfile {
            user_id: member.user_id,
            member_id: member.id,
            trip_id: member.trip_id,
            role: member.role,
            display_name: member.display_name,
            phone: member.phone_e164,
        },
    })
}
