//! Phase 3: trip archive, duplicate itinerary, PDF admin CMS upload.

use axum::extract::{Multipart, Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::models::Trip;
use crate::state::AppState;

#[derive(Serialize, FromRow)]
struct TripSummary {
    id: Uuid,
    title: String,
    year: i32,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
}

#[derive(Deserialize)]
pub struct DuplicateBody {
    pub title: String,
    pub year: i32,
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
}

async fn list_trips(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<TripSummary>>> {
    // Members see trips they belong to (multi-year archive)
    let rows: Vec<TripSummary> = sqlx::query_as(
        r#"
        SELECT t.id, t.title, t.year, t.starts_on, t.ends_on
        FROM trips t
        JOIN trip_members tm ON tm.trip_id = t.id
        WHERE tm.user_id = $1 AND tm.is_active
        ORDER BY t.year DESC, t.starts_on DESC
        "#,
    )
    .bind(user.user_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn duplicate_trip(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(source_id): Path<Uuid>,
    Json(body): Json<DuplicateBody>,
) -> ApiResult<Json<Trip>> {
    require_helper(&user)?;
    if source_id != user.trip_id {
        return Err(ApiError::Forbidden(
            "Can only duplicate the active trip from this session".into(),
        ));
    }

    let new_id = Uuid::new_v4();
    let trip: Trip = sqlx::query_as(
        r#"
        INSERT INTO trips (id, title, year, starts_on, ends_on, helpers_may_start_count)
        SELECT $1, $2, $3, $4, $5, helpers_may_start_count
        FROM trips WHERE id = $6
        RETURNING id, title, year, starts_on, ends_on, helpers_may_start_count
        "#,
    )
    .bind(new_id)
    .bind(body.title.trim())
    .bind(body.year)
    .bind(body.starts_on)
    .bind(body.ends_on)
    .bind(source_id)
    .fetch_one(&state.db)
    .await?;

    // Copy itinerary stops (shift dates by starts_on delta)
    sqlx::query(
        r#"
        INSERT INTO itinerary_stops (trip_id, day_date, starts_at, title, place_name, notes, map_url, lost_person_tip, sort_order)
        SELECT $1,
               $2 + (day_date - (SELECT starts_on FROM trips WHERE id = $3)),
               NULL,
               title, place_name, notes, map_url, lost_person_tip, sort_order
        FROM itinerary_stops
        WHERE trip_id = $3
        "#,
    )
    .bind(new_id)
    .bind(body.starts_on)
    .bind(source_id)
    .execute(&state.db)
    .await?;

    // Copy knowledge chunks (text only; embeddings re-ingested later)
    sqlx::query(
        r#"
        INSERT INTO knowledge_chunks (trip_id, source_title, source_section, content)
        SELECT $1, source_title, source_section, content
        FROM knowledge_chunks WHERE trip_id = $2
        "#,
    )
    .bind(new_id)
    .bind(source_id)
    .execute(&state.db)
    .await?;

    // Add current leader as member on new trip
    sqlx::query(
        r#"
        INSERT INTO trip_members (trip_id, user_id, role, is_kanni, is_senior)
        VALUES ($1, $2, 'leader', false, true)
        ON CONFLICT (trip_id, user_id) DO NOTHING
        "#,
    )
    .bind(new_id)
    .bind(user.user_id)
    .execute(&state.db)
    .await?;

    Ok(Json(trip))
}

/// Admin CMS: upload PDF text body for knowledge ingest (multipart field `text` or `file`).
async fn upload_knowledge_pdf(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    mut multipart: Multipart,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;
    let mut text = String::new();
    let mut source_title = "uploaded.pdf".to_string();

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| ApiError::BadRequest(e.to_string()))?
    {
        let name = field.name().unwrap_or("").to_string();
        if name == "source_title" {
            if let Ok(v) = field.text().await {
                if !v.trim().is_empty() {
                    source_title = v.trim().to_string();
                }
            }
            continue;
        }
        if name == "text" {
            text = field
                .text()
                .await
                .map_err(|e| ApiError::BadRequest(e.to_string()))?;
            continue;
        }
        if name == "file" {
            let bytes = field
                .bytes()
                .await
                .map_err(|e| ApiError::BadRequest(e.to_string()))?;
            text = pdf_extract::extract_text_from_mem(&bytes).unwrap_or_else(|_| {
                String::from_utf8_lossy(&bytes).to_string()
            });
        }
    }

    if text.trim().len() < 40 {
        return Err(ApiError::BadRequest(
            "Could not extract enough text from upload".into(),
        ));
    }

    // Chunk by paragraphs (~800 chars)
    let mut inserted = 0i32;
    let mut buf = String::new();
    let mut section_idx = 1;
    for para in text.split("\n\n") {
        let p = para.trim();
        if p.is_empty() {
            continue;
        }
        if buf.len() + p.len() > 800 && !buf.is_empty() {
            sqlx::query(
                r#"
                INSERT INTO knowledge_chunks (trip_id, source_title, source_section, content)
                VALUES ($1, $2, $3, $4)
                "#,
            )
            .bind(user.trip_id)
            .bind(&source_title)
            .bind(format!("Section {section_idx}"))
            .bind(buf.trim())
            .execute(&state.db)
            .await?;
            inserted += 1;
            section_idx += 1;
            buf.clear();
        }
        if !buf.is_empty() {
            buf.push('\n');
        }
        buf.push_str(p);
    }
    if !buf.trim().is_empty() {
        sqlx::query(
            r#"
            INSERT INTO knowledge_chunks (trip_id, source_title, source_section, content)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(user.trip_id)
        .bind(&source_title)
        .bind(format!("Section {section_idx}"))
        .bind(buf.trim())
        .execute(&state.db)
        .await?;
        inserted += 1;
    }

    Ok(Json(serde_json::json!({
        "ok": true,
        "chunks_inserted": inserted,
        "note": "Re-run ingest_pdf with OPENAI_API_KEY to embed vectors for RAG"
    })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/trips", get(list_trips))
        .route("/trips/{id}/duplicate", post(duplicate_trip))
        .route("/admin/knowledge/upload", post(upload_knowledge_pdf))
}
