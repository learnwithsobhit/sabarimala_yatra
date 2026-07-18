use axum::extract::State;
use axum::routing::{get, put};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

#[derive(Debug, Serialize, FromRow)]
struct PackingItemRow {
    id: Uuid,
    title: String,
    quantity_hint: Option<String>,
    sort_order: i32,
    checked: bool,
    updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
struct PackingProgress {
    total: i64,
    checked: i64,
    items: Vec<PackingItemRow>,
}

#[derive(Debug, Deserialize)]
struct SetCheck {
    item_id: Uuid,
    checked: bool,
}

async fn my_list(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<PackingProgress>> {
    let items: Vec<PackingItemRow> = sqlx::query_as(
        r#"
        SELECT pi.id, pi.title, pi.quantity_hint, pi.sort_order,
               COALESCE(pc.checked, FALSE) AS checked,
               pc.updated_at
        FROM packing_items pi
        LEFT JOIN packing_checks pc
          ON pc.item_id = pi.id AND pc.member_id = $2
        WHERE pi.trip_id = $1
        ORDER BY pi.sort_order, pi.title
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .fetch_all(&state.db)
    .await?;

    let total = items.len() as i64;
    let checked = items.iter().filter(|i| i.checked).count() as i64;
    Ok(Json(PackingProgress {
        total,
        checked,
        items,
    }))
}

async fn set_check(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<SetCheck>,
) -> ApiResult<Json<serde_json::Value>> {
    let item_ok: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM packing_items WHERE id = $1 AND trip_id = $2",
    )
    .bind(body.item_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if item_ok.is_none() {
        return Err(ApiError::NotFound("Packing item not found for this trip".into()));
    }

    if body.checked {
        sqlx::query(
            r#"
            INSERT INTO packing_checks (trip_id, member_id, item_id, checked, updated_at)
            VALUES ($1, $2, $3, TRUE, NOW())
            ON CONFLICT (member_id, item_id) DO UPDATE SET
                checked = TRUE,
                updated_at = NOW()
            "#,
        )
        .bind(user.trip_id)
        .bind(user.member_id)
        .bind(body.item_id)
        .execute(&state.db)
        .await?;
    } else {
        sqlx::query(
            r#"
            INSERT INTO packing_checks (trip_id, member_id, item_id, checked, updated_at)
            VALUES ($1, $2, $3, FALSE, NOW())
            ON CONFLICT (member_id, item_id) DO UPDATE SET
                checked = FALSE,
                updated_at = NOW()
            "#,
        )
        .bind(user.trip_id)
        .bind(user.member_id)
        .bind(body.item_id)
        .execute(&state.db)
        .await?;
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/packing/me", get(my_list))
        .route("/packing/check", put(set_check))
}
