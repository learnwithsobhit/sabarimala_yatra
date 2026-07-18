use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use chrono::{Duration, Utc};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use chrono::Duration as ChronoDuration;

use crate::auth::jwt::{hash_refresh_token, issue_access_token, mint_refresh_token_pair};
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
    pub refresh_token: String,
    pub expires_in_seconds: i64,
    pub user: AuthProfile,
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
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

async fn send_production_otp(config: &Config, phone: &str, code: &str) -> ApiResult<()> {
    let url = config
        .sms_webhook_url
        .as_deref()
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("SMS_WEBHOOK_URL is not configured")))?;
    let mut request = reqwest::Client::new().post(url).json(&serde_json::json!({
        "phone_e164": phone,
        "code": code,
        "message": format!("Your Swamy Sharanam login code is {code}. It expires in 10 minutes."),
        "expires_in_seconds": 600,
    }));
    if let Some(token) = config.sms_webhook_token.as_deref() {
        request = request.bearer_auth(token);
    }
    request
        .send()
        .await
        .and_then(reqwest::Response::error_for_status)
        .map_err(|error| {
            tracing::error!(%error, "OTP webhook delivery failed");
            ApiError::Internal(anyhow::anyhow!("OTP delivery failed"))
        })?;
    Ok(())
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

    let recent: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*)
        FROM otp_challenges
        WHERE phone_e164 = $1 AND created_at > NOW() - INTERVAL '15 minutes'
        "#,
    )
    .bind(&phone)
    .fetch_one(db)
    .await?;
    if recent.0 >= 5 {
        return Err(ApiError::TooManyRequests(
            "Too many OTP requests. Wait 15 minutes and try again.".into(),
        ));
    }
    let sent_too_recently: bool = sqlx::query_scalar(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM otp_challenges
            WHERE phone_e164 = $1 AND created_at > NOW() - INTERVAL '60 seconds'
        )
        "#,
    )
    .bind(&phone)
    .fetch_one(db)
    .await?;
    if sent_too_recently {
        return Err(ApiError::TooManyRequests(
            "Please wait one minute before requesting another OTP.".into(),
        ));
    }

    let code = if config.dev_auth {
        config.dev_otp_code.clone()
    } else {
        format!("{:06}", rand::random::<u32>() % 1_000_000)
    };

    let hash = hash_code(&code)?;
    let expires = Utc::now() + Duration::minutes(10);

    let challenge_id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO otp_challenges (phone_e164, code_hash, expires_at)
           VALUES ($1, $2, $3)
           RETURNING id"#,
    )
    .bind(&phone)
    .bind(&hash)
    .bind(expires)
    .fetch_one(db)
    .await?;

    if !config.dev_auth {
        if let Err(error) = send_production_otp(config, &phone, &code).await {
            if let Err(delete_error) = sqlx::query("DELETE FROM otp_challenges WHERE id = $1")
                .bind(challenge_id)
                .execute(db)
                .await
            {
                tracing::error!(%delete_error, %challenge_id, "failed to remove undelivered OTP");
            }
            return Err(error);
        }
    }

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
        let row: Option<(
            Uuid,
            String,
            chrono::DateTime<Utc>,
            Option<chrono::DateTime<Utc>>,
            i32,
        )> =
            sqlx::query_as(
                r#"SELECT id, code_hash, expires_at, consumed_at, attempt_count
                   FROM otp_challenges
                   WHERE phone_e164 = $1
                   ORDER BY created_at DESC
                   LIMIT 1"#,
            )
            .bind(&phone)
            .fetch_optional(db)
            .await?;

        let Some((id, hash, expires, consumed, attempt_count)) = row else {
            return Err(ApiError::Unauthorized("No OTP requested".into()));
        };
        if consumed.is_some() {
            return Err(ApiError::Unauthorized("OTP already used".into()));
        }
        if expires < Utc::now() {
            return Err(ApiError::Unauthorized("OTP expired".into()));
        }
        if attempt_count >= 5 {
            return Err(ApiError::TooManyRequests(
                "Too many incorrect attempts. Request a new OTP.".into(),
            ));
        }
        if !verify_code(code, &hash) {
            sqlx::query("UPDATE otp_challenges SET attempt_count = attempt_count + 1 WHERE id = $1")
                .bind(id)
                .execute(db)
                .await?;
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

    issue_session(db, config, &member).await
}

async fn issue_session(
    db: &PgPool,
    config: &Config,
    member: &TripMemberRow,
) -> ApiResult<AuthResponse> {
    let access = issue_access_token(
        &config.jwt_secret,
        member.user_id,
        member.id,
        member.trip_id,
        member.role,
        member.display_name.clone(),
        member.phone_e164.clone(),
    )?;
    let (refresh_raw, refresh_hash) = mint_refresh_token_pair();
    let expires = Utc::now() + ChronoDuration::days(30);
    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (user_id, member_id, token_hash, expires_at)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(member.user_id)
    .bind(member.id)
    .bind(&refresh_hash)
    .bind(expires)
    .execute(db)
    .await?;

    Ok(AuthResponse {
        access_token: access,
        refresh_token: refresh_raw,
        expires_in_seconds: 7200,
        user: AuthProfile {
            user_id: member.user_id,
            member_id: member.id,
            trip_id: member.trip_id,
            role: member.role,
            display_name: member.display_name.clone(),
            phone: member.phone_e164.clone(),
        },
    })
}

pub async fn refresh_session(
    db: &PgPool,
    config: &Config,
    refresh_token: &str,
) -> ApiResult<AuthResponse> {
    let hash = hash_refresh_token(refresh_token.trim());
    let row: Option<(Uuid, Uuid, chrono::DateTime<Utc>, Option<chrono::DateTime<Utc>>)> =
        sqlx::query_as(
            r#"
            SELECT id, member_id, expires_at, revoked_at
            FROM refresh_tokens
            WHERE token_hash = $1
            "#,
        )
        .bind(&hash)
        .fetch_optional(db)
        .await?;

    let Some((id, member_id, expires_at, revoked_at)) = row else {
        return Err(ApiError::Unauthorized("Invalid refresh token".into()));
    };
    if revoked_at.is_some() || expires_at < Utc::now() {
        return Err(ApiError::Unauthorized("Refresh token expired".into()));
    }

    // Rotate: revoke old token
    sqlx::query("UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;

    let member: TripMemberRow = sqlx::query_as(
        r#"
        SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
               u.display_name, u.phone_e164, tm.is_active
        FROM trip_members tm
        JOIN users u ON u.id = tm.user_id
        WHERE tm.id = $1 AND tm.is_active
        "#,
    )
    .bind(member_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| ApiError::Unauthorized("Membership no longer active".into()))?;

    issue_session(db, config, &member).await
}
