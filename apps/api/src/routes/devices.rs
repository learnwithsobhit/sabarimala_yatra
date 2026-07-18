use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::error::ApiResult;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct RegisterDevice {
    pub fcm_token: String,
    pub platform: Option<String>,
}

#[derive(Debug, Serialize, FromRow)]
struct DeviceRow {
    id: Uuid,
    member_id: Uuid,
    fcm_token: String,
    platform: Option<String>,
    updated_at: DateTime<Utc>,
}

async fn register(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<RegisterDevice>,
) -> ApiResult<Json<serde_json::Value>> {
    let token = body.fcm_token.trim();
    if token.is_empty() {
        return Ok(Json(serde_json::json!({ "ok": false, "error": "empty token" })));
    }

    sqlx::query(
        r#"
        INSERT INTO device_tokens (member_id, trip_id, fcm_token, platform, updated_at)
        VALUES ($1, $2, $3, $4, NOW())
        ON CONFLICT (fcm_token) DO UPDATE SET
            member_id = EXCLUDED.member_id,
            trip_id = EXCLUDED.trip_id,
            platform = EXCLUDED.platform,
            updated_at = NOW()
        "#,
    )
    .bind(user.member_id)
    .bind(user.trip_id)
    .bind(token)
    .bind(body.platform)
    .execute(&state.db)
    .await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn my_devices(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<DeviceRow>>> {
    let rows: Vec<DeviceRow> = sqlx::query_as(
        r#"
        SELECT id, member_id, fcm_token, platform, updated_at
        FROM device_tokens
        WHERE member_id = $1
        ORDER BY updated_at DESC
        "#,
    )
    .bind(user.member_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/devices/register", post(register))
        .route("/devices/me", get(my_devices))
}
