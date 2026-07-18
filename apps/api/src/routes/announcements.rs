use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::models::{Announcement, AnnouncementPriority};
use crate::push;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct CreateAnnouncement {
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub priority: Option<AnnouncementPriority>,
}

#[derive(Deserialize)]
pub struct SosBody {
    pub spot: String,
}

async fn list(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<Announcement>>> {
    let rows: Vec<Announcement> = sqlx::query_as(
        r#"
        SELECT id, trip_id, author_id, priority, title, body, count_session_id, created_at
        FROM announcements
        WHERE trip_id = $1
        ORDER BY created_at DESC
        LIMIT 50
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn create(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateAnnouncement>,
) -> ApiResult<Json<Announcement>> {
    require_helper(&user)?;
    state.rate_limit.check_member_announce(user.member_id)?;
    let priority = body.priority.unwrap_or(AnnouncementPriority::Info);
    let row = insert_announcement(
        &state,
        user.trip_id,
        user.member_id,
        priority,
        body.title.trim(),
        body.body.trim(),
    )
    .await?;
    Ok(Json(row))
}

async fn sos(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<SosBody>,
) -> ApiResult<Json<Announcement>> {
    let spot = body.spot.trim();
    if spot.is_empty() {
        return Err(ApiError::BadRequest("spot is required".into()));
    }
    let title = format!("SOS — {} needs help", user.display_name);
    let msg = format!(
        "{} is lost / separated and waiting at: {spot}. Please help rendezvous. Do not panic — follow trip rendezvous points.",
        user.display_name
    );
    let row = insert_announcement(
        &state,
        user.trip_id,
        user.member_id,
        AnnouncementPriority::Urgent,
        &title,
        &msg,
    )
    .await?;
    Ok(Json(row))
}

async fn insert_announcement(
    state: &AppState,
    trip_id: uuid::Uuid,
    author_id: uuid::Uuid,
    priority: AnnouncementPriority,
    title: &str,
    body: &str,
) -> ApiResult<Announcement> {
    let row: Announcement = sqlx::query_as(
        r#"
        INSERT INTO announcements (trip_id, author_id, priority, title, body)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, trip_id, author_id, priority, title, body, count_session_id, created_at
        "#,
    )
    .bind(trip_id)
    .bind(author_id)
    .bind(priority)
    .bind(title)
    .bind(body)
    .fetch_one(&state.db)
    .await?;

    let high = matches!(priority, AnnouncementPriority::Urgent);
    push::notify_trip(
        &state.db,
        &state.push,
        trip_id,
        title,
        body,
        serde_json::json!({
            "type": "announcement",
            "announcement_id": row.id.to_string(),
            "priority": if high { "urgent" } else { "info" },
        }),
        high,
    )
    .await;

    if let Err(error) = sqlx::query(
        r#"
        INSERT INTO audit_events
            (trip_id, actor_member_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, $2, 'announcement.create', 'announcement', $3, $4)
        "#,
    )
    .bind(trip_id)
    .bind(author_id)
    .bind(row.id)
    .bind(serde_json::json!({
        "title": title,
        "priority": priority,
    }))
    .execute(&state.db)
    .await
    {
        tracing::error!(%error, announcement_id = %row.id, "failed to write announcement audit");
    }

    Ok(row)
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/announcements", get(list).post(create))
        .route("/announcements/sos", post(sos))
}
