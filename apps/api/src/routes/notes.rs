//! Phase 2: day notes, mala reminders, feedback. Phase 3: registration interest.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

#[derive(Deserialize)]
pub struct DayQuery {
    pub day: Option<NaiveDate>,
}

#[derive(Serialize, FromRow)]
struct DayNote {
    id: Uuid,
    day_date: NaiveDate,
    author_id: Uuid,
    author_name: String,
    body: String,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Deserialize)]
pub struct CreateNote {
    pub day_date: NaiveDate,
    pub body: String,
}

#[derive(Serialize, FromRow)]
struct MalaReminder {
    id: Uuid,
    title: String,
    body: String,
    remind_on: NaiveDate,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Deserialize)]
pub struct CreateMala {
    pub title: String,
    pub body: String,
    pub remind_on: NaiveDate,
}

#[derive(Serialize, FromRow)]
struct FeedbackRow {
    id: Uuid,
    member_id: Uuid,
    rating: Option<i32>,
    lessons: Option<String>,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Deserialize)]
pub struct UpsertFeedback {
    pub rating: Option<i32>,
    pub lessons: Option<String>,
}

#[derive(Deserialize)]
pub struct DayStatusBody {
    pub member_id: Uuid,
    pub day_date: NaiveDate,
    pub status: String,
    pub note: Option<String>,
}

#[derive(Serialize, FromRow)]
struct DayStatusRow {
    member_id: Uuid,
    display_name: String,
    day_date: NaiveDate,
    status: String,
    note: Option<String>,
}

#[derive(Deserialize)]
pub struct RegistrationBody {
    pub year_interest: i32,
    pub phone_e164: String,
    pub display_name: String,
    pub notes: Option<String>,
}

async fn list_notes(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Query(q): Query<DayQuery>,
) -> ApiResult<Json<Vec<DayNote>>> {
    let rows: Vec<DayNote> = if let Some(day) = q.day {
        sqlx::query_as(
            r#"
            SELECT n.id, n.day_date, n.author_id, u.display_name AS author_name, n.body, n.created_at
            FROM day_notes n
            JOIN trip_members tm ON tm.id = n.author_id
            JOIN users u ON u.id = tm.user_id
            WHERE n.trip_id = $1 AND n.day_date = $2
            ORDER BY n.created_at DESC
            "#,
        )
        .bind(user.trip_id)
        .bind(day)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query_as(
            r#"
            SELECT n.id, n.day_date, n.author_id, u.display_name AS author_name, n.body, n.created_at
            FROM day_notes n
            JOIN trip_members tm ON tm.id = n.author_id
            JOIN users u ON u.id = tm.user_id
            WHERE n.trip_id = $1
            ORDER BY n.day_date DESC, n.created_at DESC
            LIMIT 100
            "#,
        )
        .bind(user.trip_id)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(rows))
}

async fn create_note(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateNote>,
) -> ApiResult<Json<serde_json::Value>> {
    let text = body.body.trim();
    if text.is_empty() {
        return Err(ApiError::BadRequest("Note body is required".into()));
    }
    let id: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO day_notes (trip_id, day_date, author_id, body)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        "#,
    )
    .bind(user.trip_id)
    .bind(body.day_date)
    .bind(user.member_id)
    .bind(text)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "id": id.0, "ok": true })))
}

async fn list_mala(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<MalaReminder>>> {
    let rows: Vec<MalaReminder> = sqlx::query_as(
        r#"
        SELECT id, title, body, remind_on, created_at
        FROM mala_reminders
        WHERE trip_id = $1
        ORDER BY remind_on ASC
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn create_mala(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateMala>,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;
    let id: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO mala_reminders (trip_id, title, body, remind_on, created_by)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        "#,
    )
    .bind(user.trip_id)
    .bind(body.title.trim())
    .bind(body.body.trim())
    .bind(body.remind_on)
    .bind(user.member_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "id": id.0, "ok": true })))
}

async fn upsert_feedback(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<UpsertFeedback>,
) -> ApiResult<Json<FeedbackRow>> {
    if let Some(r) = body.rating {
        if !(1..=5).contains(&r) {
            return Err(ApiError::BadRequest("rating must be 1–5".into()));
        }
    }
    let row: FeedbackRow = sqlx::query_as(
        r#"
        INSERT INTO trip_feedback (trip_id, member_id, rating, lessons)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (trip_id, member_id) DO UPDATE SET
            rating = EXCLUDED.rating,
            lessons = EXCLUDED.lessons
        RETURNING id, member_id, rating, lessons, created_at
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(body.rating)
    .bind(body.lessons)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

async fn my_feedback(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Option<FeedbackRow>>> {
    let row: Option<FeedbackRow> = sqlx::query_as(
        r#"
        SELECT id, member_id, rating, lessons, created_at
        FROM trip_feedback
        WHERE trip_id = $1 AND member_id = $2
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .fetch_optional(&state.db)
    .await?;
    Ok(Json(row))
}

async fn set_day_status(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<DayStatusBody>,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;
    if body.status != "traveling" && body.status != "not_traveling" {
        return Err(ApiError::BadRequest(
            "status must be traveling or not_traveling".into(),
        ));
    }
    let member_ok: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM trip_members WHERE id = $1 AND trip_id = $2 AND is_active",
    )
    .bind(body.member_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if member_ok.is_none() {
        return Err(ApiError::NotFound("Member not on this trip".into()));
    }
    sqlx::query(
        r#"
        INSERT INTO trip_member_day_status (trip_id, member_id, day_date, status, note, set_by, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW())
        ON CONFLICT (member_id, day_date) DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            set_by = EXCLUDED.set_by,
            updated_at = NOW()
        "#,
    )
    .bind(user.trip_id)
    .bind(body.member_id)
    .bind(body.day_date)
    .bind(&body.status)
    .bind(&body.note)
    .bind(user.member_id)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn list_day_status(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(day): Path<NaiveDate>,
) -> ApiResult<Json<Vec<DayStatusRow>>> {
    let rows: Vec<DayStatusRow> = sqlx::query_as(
        r#"
        SELECT ds.member_id, u.display_name, ds.day_date, ds.status, ds.note
        FROM trip_member_day_status ds
        JOIN trip_members tm ON tm.id = ds.member_id
        JOIN users u ON u.id = tm.user_id
        WHERE ds.trip_id = $1 AND ds.day_date = $2
        ORDER BY u.display_name
        "#,
    )
    .bind(user.trip_id)
    .bind(day)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn register_interest(
    State(state): State<AppState>,
    Json(body): Json<RegistrationBody>,
) -> ApiResult<Json<serde_json::Value>> {
    // Public-ish: no auth required for next-year interest; still rate lightly via empty phone check
    let phone = body.phone_e164.trim();
    let name = body.display_name.trim();
    if phone.len() < 10 || name.is_empty() {
        return Err(ApiError::BadRequest("phone and name required".into()));
    }
    let id: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO registration_interest (year_interest, phone_e164, display_name, notes)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        "#,
    )
    .bind(body.year_interest)
    .bind(phone)
    .bind(name)
    .bind(&body.notes)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "id": id.0, "ok": true })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/notes", get(list_notes).post(create_note))
        .route("/mala-reminders", get(list_mala).post(create_mala))
        .route("/feedback", get(my_feedback).post(upsert_feedback))
        .route("/day-status", post(set_day_status))
        .route("/day-status/{day}", get(list_day_status))
        .route("/registration/interest", post(register_interest))
}
