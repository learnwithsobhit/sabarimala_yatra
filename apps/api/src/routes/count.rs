use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::models::{
    CountMarkStatus, CountScopeKind, CountSession, CountSessionStatus, TripMemberRow,
};
use crate::push;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct StartCountBody {
    pub checkpoint_label: String,
    #[serde(default)]
    pub scope_kind: Option<CountScopeKind>,
    pub scope_vehicle_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
pub struct MarkPresentBody {
    /// Idempotency / offline sync key
    pub client_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct HelperMarkBody {
    pub member_id: Uuid,
    pub status: CountMarkStatus,
}

#[derive(Debug, Deserialize)]
pub struct StopCountBody {
    pub ready_to_march_note: Option<String>,
    /// Allow stop even if present < expected
    #[serde(default)]
    pub force: bool,
}

#[derive(Debug, Serialize)]
pub struct CountBoard {
    pub session: CountSession,
    pub present_count: i64,
    pub expected_count: i32,
    pub present: Vec<BoardMember>,
    pub not_yet: Vec<BoardMember>,
    pub missing: Vec<BoardMember>,
    pub my_status: Option<CountMarkStatus>,
}

#[derive(Debug, Serialize)]
pub struct BoardMember {
    pub member_id: Uuid,
    pub display_name: String,
    pub phone_e164: String,
    pub status: Option<CountMarkStatus>,
}

async fn start_count(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<StartCountBody>,
) -> ApiResult<Json<CountSession>> {
    let trip: (bool,) =
        sqlx::query_as("SELECT helpers_may_start_count FROM trips WHERE id = $1")
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?;

    if !user.role.can_start_count(trip.0) {
        return Err(ApiError::Forbidden(
            "Only leader (or volunteer if enabled) can start a count session".into(),
        ));
    }

    let label = body.checkpoint_label.trim();
    if label.is_empty() {
        return Err(ApiError::BadRequest("checkpoint_label is required".into()));
    }

    let scope_kind = body.scope_kind.unwrap_or(CountScopeKind::All);
    if matches!(scope_kind, CountScopeKind::Bus) && body.scope_vehicle_id.is_none() {
        return Err(ApiError::BadRequest(
            "scope_vehicle_id required when scope is bus".into(),
        ));
    }

    let open: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM count_sessions WHERE trip_id = $1 AND status = 'open'",
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if open.is_some() {
        return Err(ApiError::Conflict(
            "A count session is already open. Stop it before starting another.".into(),
        ));
    }

    let expected: (i64,) = match scope_kind {
        CountScopeKind::All => {
            sqlx::query_as(
                "SELECT COUNT(*) FROM trip_members WHERE trip_id = $1 AND is_active",
            )
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?
        }
        CountScopeKind::Bus => {
            sqlx::query_as(
                r#"
                SELECT COUNT(*)
                FROM trip_members tm
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

    let session_id = Uuid::new_v4();
    let session: CountSession = sqlx::query_as(
        r#"
        INSERT INTO count_sessions (
            id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id,
            status, expected_count, started_by
        ) VALUES ($1, $2, $3, $4, $5, 'open', $6, $7)
        RETURNING id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
                  expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        "#,
    )
    .bind(session_id)
    .bind(user.trip_id)
    .bind(label)
    .bind(scope_kind)
    .bind(body.scope_vehicle_id)
    .bind(expected.0 as i32)
    .bind(user.member_id)
    .fetch_one(&state.db)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO announcements (trip_id, author_id, priority, title, body, count_session_id)
        VALUES ($1, $2, 'urgent', $3, $4, $5)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(format!("Count open — {label}"))
    .bind("Please tap I am Present in the app now.".to_string())
    .bind(session.id)
    .execute(&state.db)
    .await?;

    push::notify_trip(
        &state.db,
        &state.push,
        user.trip_id,
        &format!("Count open — {label}"),
        "Please tap I am Present in the app now.",
        serde_json::json!({
            "type": "count_open",
            "session_id": session.id.to_string(),
            "checkpoint": label,
        }),
        true,
    )
    .await;

    sqlx::query(
        r#"
        INSERT INTO audit_events (trip_id, actor_member_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, $2, 'count.start', 'count_session', $3, $4)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(session.id)
    .bind(serde_json::json!({ "checkpoint": label }))
    .execute(&state.db)
    .await?;

    Ok(Json(session))
}

async fn open_session(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Option<CountSession>>> {
    let session: Option<CountSession> = sqlx::query_as(
        r#"
        SELECT id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
               expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        FROM count_sessions
        WHERE trip_id = $1 AND status = 'open'
        LIMIT 1
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
) -> ApiResult<Json<CountBoard>> {
    let session: CountSession = sqlx::query_as(
        r#"
        SELECT id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
               expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        FROM count_sessions WHERE id = $1 AND trip_id = $2
        "#,
    )
    .bind(session_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::NotFound("Count session not found".into()))?;

    let members: Vec<TripMemberRow> = match session.scope_kind {
        CountScopeKind::All => {
            sqlx::query_as(
                r#"
                SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
                       u.display_name, u.phone_e164, tm.is_active
                FROM trip_members tm
                JOIN users u ON u.id = tm.user_id
                WHERE tm.trip_id = $1 AND tm.is_active
                ORDER BY u.display_name
                "#,
            )
            .bind(user.trip_id)
            .fetch_all(&state.db)
            .await?
        }
        CountScopeKind::Bus => {
            sqlx::query_as(
                r#"
                SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
                       u.display_name, u.phone_e164, tm.is_active
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

    let marks: Vec<(Uuid, CountMarkStatus)> = sqlx::query_as(
        "SELECT member_id, status FROM count_marks WHERE session_id = $1",
    )
    .bind(session_id)
    .fetch_all(&state.db)
    .await?;

    let mark_map: std::collections::HashMap<Uuid, CountMarkStatus> =
        marks.into_iter().collect();

    let mut present = Vec::new();
    let mut not_yet = Vec::new();
    let mut missing = Vec::new();
    let mut my_status = None;

    for m in members {
        let status = mark_map.get(&m.id).copied();
        if m.id == user.member_id {
            my_status = status;
        }
        let row = BoardMember {
            member_id: m.id,
            display_name: m.display_name,
            phone_e164: m.phone_e164,
            status,
        };
        match status {
            Some(CountMarkStatus::Present) => present.push(row),
            Some(CountMarkStatus::Missing) | Some(CountMarkStatus::Excused) => {
                missing.push(row)
            }
            None => not_yet.push(row),
        }
    }

    let present_count = present.len() as i64;
    let expected_count = session.expected_count;

    Ok(Json(CountBoard {
        session,
        present_count,
        expected_count,
        present,
        not_yet,
        missing,
        my_status,
    }))
}

async fn mark_self_present(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
    Json(body): Json<MarkPresentBody>,
) -> ApiResult<Json<serde_json::Value>> {
    let session: CountSession = sqlx::query_as(
        r#"
        SELECT id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
               expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        FROM count_sessions WHERE id = $1 AND trip_id = $2
        "#,
    )
    .bind(session_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::NotFound("Count session not found".into()))?;

    if session.status != CountSessionStatus::Open {
        return Err(ApiError::Conflict(
            "Count session is closed — marks are locked".into(),
        ));
    }

    sqlx::query(
        r#"
        INSERT INTO count_marks (session_id, member_id, status, source, marked_by, client_id)
        VALUES ($1, $2, 'present', 'self', $2, $3)
        ON CONFLICT (session_id, member_id) DO UPDATE
          SET status = 'present',
              source = 'self',
              marked_by = EXCLUDED.marked_by,
              marked_at = NOW(),
              client_id = COALESCE(EXCLUDED.client_id, count_marks.client_id)
        "#,
    )
    .bind(session_id)
    .bind(user.member_id)
    .bind(body.client_id)
    .execute(&state.db)
    .await?;

    Ok(Json(serde_json::json!({
        "ok": true,
        "member_id": user.member_id,
        "status": "present"
    })))
}

async fn helper_mark(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
    Json(body): Json<HelperMarkBody>,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;

    let status: CountSessionStatus =
        sqlx::query_scalar("SELECT status FROM count_sessions WHERE id = $1 AND trip_id = $2")
            .bind(session_id)
            .bind(user.trip_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or_else(|| ApiError::NotFound("Count session not found".into()))?;

    if status != CountSessionStatus::Open {
        return Err(ApiError::Conflict("Count session is closed".into()));
    }

    let in_trip: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM trip_members WHERE id = $1 AND trip_id = $2 AND is_active",
    )
    .bind(body.member_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if in_trip.is_none() {
        return Err(ApiError::BadRequest(
            "member_id is not an active member of this trip".into(),
        ));
    }

    sqlx::query(
        r#"
        INSERT INTO count_marks (session_id, member_id, status, source, marked_by)
        VALUES ($1, $2, $3, 'helper', $4)
        ON CONFLICT (session_id, member_id) DO UPDATE
          SET status = EXCLUDED.status,
              source = 'helper',
              marked_by = EXCLUDED.marked_by,
              marked_at = NOW()
        "#,
    )
    .bind(session_id)
    .bind(body.member_id)
    .bind(body.status)
    .bind(user.member_id)
    .execute(&state.db)
    .await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn stop_count(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(session_id): Path<Uuid>,
    Json(body): Json<StopCountBody>,
) -> ApiResult<Json<CountSession>> {
    let trip: (bool,) =
        sqlx::query_as("SELECT helpers_may_start_count FROM trips WHERE id = $1")
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?;

    if !user.role.can_start_count(trip.0) {
        return Err(ApiError::Forbidden(
            "Only leader (or volunteer if enabled) can stop a count session".into(),
        ));
    }

    let session: CountSession = sqlx::query_as(
        r#"
        SELECT id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
               expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        FROM count_sessions WHERE id = $1 AND trip_id = $2
        "#,
    )
    .bind(session_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::NotFound("Count session not found".into()))?;

    if session.status != CountSessionStatus::Open {
        return Err(ApiError::Conflict("Session already closed".into()));
    }

    let present: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM count_marks WHERE session_id = $1 AND status = 'present'",
    )
    .bind(session_id)
    .fetch_one(&state.db)
    .await?;

    if !body.force && present.0 < session.expected_count as i64 {
        return Err(ApiError::Conflict(format!(
            "Present {}/{} — set force=true to stop anyway with a note",
            present.0, session.expected_count
        )));
    }

    let closed: CountSession = sqlx::query_as(
        r#"
        UPDATE count_sessions
        SET status = 'closed',
            closed_by = $2,
            closed_at = NOW(),
            ready_to_march_note = $3
        WHERE id = $1
        RETURNING id, trip_id, checkpoint_label, scope_kind, scope_vehicle_id, status,
                  expected_count, started_by, started_at, closed_by, closed_at, ready_to_march_note
        "#,
    )
    .bind(session_id)
    .bind(user.member_id)
    .bind(body.ready_to_march_note.clone())
    .fetch_one(&state.db)
    .await?;

    let note = body
        .ready_to_march_note
        .unwrap_or_else(|| "All clear — ready to march.".into());

    sqlx::query(
        r#"
        INSERT INTO announcements (trip_id, author_id, priority, title, body, count_session_id)
        VALUES ($1, $2, 'urgent', $3, $4, $5)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(format!(
        "Count closed — {}",
        closed.checkpoint_label
    ))
    .bind(format!(
        "Present {}/{}. {note}",
        present.0, closed.expected_count
    ))
    .bind(session_id)
    .execute(&state.db)
    .await?;

    let close_title = format!("Count closed — {}", closed.checkpoint_label);
    let close_body = format!(
        "Present {}/{}. {note}",
        present.0, closed.expected_count
    );
    push::notify_trip(
        &state.db,
        &state.push,
        user.trip_id,
        &close_title,
        &close_body,
        serde_json::json!({
            "type": "count_closed",
            "session_id": session_id.to_string(),
        }),
        true,
    )
    .await;

    Ok(Json(closed))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/count/sessions/open", get(open_session))
        .route("/count/sessions", post(start_count))
        .route("/count/sessions/{session_id}/board", get(board))
        .route(
            "/count/sessions/{session_id}/present",
            post(mark_self_present),
        )
        .route("/count/sessions/{session_id}/mark", post(helper_mark))
        .route("/count/sessions/{session_id}/stop", post(stop_count))
}
