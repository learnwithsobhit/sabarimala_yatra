use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "food_session_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
enum FoodSessionStatus {
    Open,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "food_scope_kind", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
enum FoodScopeKind {
    All,
    Bus,
}

#[derive(Debug, Serialize, FromRow)]
struct FoodSession {
    id: Uuid,
    trip_id: Uuid,
    label: String,
    scope_kind: FoodScopeKind,
    scope_vehicle_id: Option<Uuid>,
    status: FoodSessionStatus,
    expected_count: i32,
    started_by: Uuid,
    started_at: DateTime<Utc>,
    closed_by: Option<Uuid>,
    closed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
struct StartFood {
    label: String,
    #[serde(default)]
    scope_kind: Option<FoodScopeKind>,
    scope_vehicle_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
struct MarkFood {
    member_id: Option<Uuid>,
    #[serde(default = "default_true")]
    received: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Serialize)]
struct FoodBoard {
    session: FoodSession,
    served_count: i64,
    expected_count: i32,
    served: Vec<BoardRow>,
    pending: Vec<BoardRow>,
    my_received: Option<bool>,
}

#[derive(Debug, Serialize)]
struct BoardRow {
    member_id: Uuid,
    display_name: String,
    phone_e164: String,
    received: Option<bool>,
}

async fn start(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<StartFood>,
) -> ApiResult<Json<FoodSession>> {
    require_helper(&user)?;
    let label = body.label.trim();
    if label.is_empty() {
        return Err(ApiError::BadRequest("label required".into()));
    }
    let scope = body.scope_kind.unwrap_or(FoodScopeKind::All);
    if matches!(scope, FoodScopeKind::Bus) && body.scope_vehicle_id.is_none() {
        return Err(ApiError::BadRequest("scope_vehicle_id required for bus".into()));
    }

    let open: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM food_sessions WHERE trip_id = $1 AND status = 'open'",
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if open.is_some() {
        return Err(ApiError::Conflict(
            "A food session is already open — close it first".into(),
        ));
    }

    let expected: (i64,) = match scope {
        FoodScopeKind::All => {
            sqlx::query_as(
                "SELECT COUNT(*) FROM trip_members WHERE trip_id = $1 AND is_active",
            )
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?
        }
        FoodScopeKind::Bus => {
            sqlx::query_as(
                r#"
                SELECT COUNT(*) FROM trip_members tm
                JOIN assignments a ON a.member_id = tm.id
                WHERE tm.trip_id = $1 AND tm.is_active AND a.vehicle_id = $2
                "#,
            )
            .bind(user.trip_id)
            .bind(body.scope_vehicle_id)
            .fetch_one(&state.db)
            .await?
        }
    };

    let session: FoodSession = sqlx::query_as(
        r#"
        INSERT INTO food_sessions (trip_id, label, scope_kind, scope_vehicle_id, expected_count, started_by)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, trip_id, label, scope_kind, scope_vehicle_id, status, expected_count,
                  started_by, started_at, closed_by, closed_at
        "#,
    )
    .bind(user.trip_id)
    .bind(label)
    .bind(scope)
    .bind(body.scope_vehicle_id)
    .bind(expected.0 as i32)
    .bind(user.member_id)
    .fetch_one(&state.db)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO announcements (trip_id, author_id, priority, title, body)
        VALUES ($1, $2, 'info', $3, $4)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(format!("Food distribution — {label}"))
    .bind("Please collect your meal and tap Received if asked.".to_string())
    .execute(&state.db)
    .await?;

    Ok(Json(session))
}

async fn open_session(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Option<FoodSession>>> {
    let session: Option<FoodSession> = sqlx::query_as(
        r#"
        SELECT id, trip_id, label, scope_kind, scope_vehicle_id, status, expected_count,
               started_by, started_at, closed_by, closed_at
        FROM food_sessions WHERE trip_id = $1 AND status = 'open' LIMIT 1
        "#,
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    Ok(Json(session))
}

async fn board(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
) -> ApiResult<Json<FoodBoard>> {
    let session: FoodSession = sqlx::query_as(
        r#"
        SELECT id, trip_id, label, scope_kind, scope_vehicle_id, status, expected_count,
               started_by, started_at, closed_by, closed_at
        FROM food_sessions WHERE id = $1 AND trip_id = $2
        "#,
    )
    .bind(session_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::NotFound("Food session not found".into()))?;

    let expected_count = session.expected_count;

    #[derive(FromRow)]
    struct MemberLite {
        id: Uuid,
        display_name: String,
        phone_e164: String,
    }

    let members: Vec<MemberLite> = match session.scope_kind {
        FoodScopeKind::All => {
            sqlx::query_as(
                r#"
                SELECT tm.id, u.display_name, u.phone_e164
                FROM trip_members tm JOIN users u ON u.id = tm.user_id
                WHERE tm.trip_id = $1 AND tm.is_active ORDER BY u.display_name
                "#,
            )
            .bind(user.trip_id)
            .fetch_all(&state.db)
            .await?
        }
        FoodScopeKind::Bus => {
            sqlx::query_as(
                r#"
                SELECT tm.id, u.display_name, u.phone_e164
                FROM trip_members tm
                JOIN users u ON u.id = tm.user_id
                JOIN assignments a ON a.member_id = tm.id
                WHERE tm.trip_id = $1 AND tm.is_active AND a.vehicle_id = $2
                ORDER BY u.display_name
                "#,
            )
            .bind(user.trip_id)
            .bind(session.scope_vehicle_id)
            .fetch_all(&state.db)
            .await?
        }
    };

    let marks: Vec<(Uuid, bool)> =
        sqlx::query_as("SELECT member_id, received FROM food_marks WHERE session_id = $1")
            .bind(session_id)
            .fetch_all(&state.db)
            .await?;
    let map: std::collections::HashMap<Uuid, bool> = marks.into_iter().collect();

    let mut served = Vec::new();
    let mut pending = Vec::new();
    let mut my_received = None;
    for m in members {
        let received = map.get(&m.id).copied();
        if m.id == user.member_id {
            my_received = received;
        }
        let row = BoardRow {
            member_id: m.id,
            display_name: m.display_name,
            phone_e164: m.phone_e164,
            received,
        };
        if received == Some(true) {
            served.push(row);
        } else {
            pending.push(row);
        }
    }

    Ok(Json(FoodBoard {
        session,
        served_count: served.len() as i64,
        expected_count,
        served,
        pending,
        my_received,
    }))
}

async fn mark(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
    Json(body): Json<MarkFood>,
) -> ApiResult<Json<serde_json::Value>> {
    let status: FoodSessionStatus =
        sqlx::query_scalar("SELECT status FROM food_sessions WHERE id = $1 AND trip_id = $2")
            .bind(session_id)
            .bind(user.trip_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or_else(|| ApiError::NotFound("Food session not found".into()))?;
    if status != FoodSessionStatus::Open {
        return Err(ApiError::Conflict("Food session closed".into()));
    }

    let target = body.member_id.unwrap_or(user.member_id);
    if target != user.member_id && !user.role.can_help_mark() {
        return Err(ApiError::Forbidden("Only helpers can mark others".into()));
    }

    sqlx::query(
        r#"
        INSERT INTO food_marks (session_id, member_id, received, marked_by)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (session_id, member_id) DO UPDATE SET
            received = EXCLUDED.received,
            marked_by = EXCLUDED.marked_by,
            marked_at = NOW()
        "#,
    )
    .bind(session_id)
    .bind(target)
    .bind(body.received)
    .bind(user.member_id)
    .execute(&state.db)
    .await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn stop(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
) -> ApiResult<Json<FoodSession>> {
    require_helper(&user)?;
    let session: FoodSession = sqlx::query_as(
        r#"
        UPDATE food_sessions
        SET status = 'closed', closed_by = $2, closed_at = NOW()
        WHERE id = $1 AND trip_id = $3 AND status = 'open'
        RETURNING id, trip_id, label, scope_kind, scope_vehicle_id, status, expected_count,
                  started_by, started_at, closed_by, closed_at
        "#,
    )
    .bind(session_id)
    .bind(user.member_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::Conflict("No open food session to close".into()))?;

    Ok(Json(session))
}

async fn history(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<FoodSession>>> {
    let rows: Vec<FoodSession> = sqlx::query_as(
        r#"
        SELECT id, trip_id, label, scope_kind, scope_vehicle_id, status, expected_count,
               started_by, started_at, closed_by, closed_at
        FROM food_sessions WHERE trip_id = $1
        ORDER BY started_at DESC LIMIT 20
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/food/sessions", post(start).get(history))
        .route("/food/sessions/open", get(open_session))
        .route("/food/sessions/{session_id}/board", get(board))
        .route("/food/sessions/{session_id}/mark", post(mark))
        .route("/food/sessions/{session_id}/stop", post(stop))
}
