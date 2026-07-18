use axum::extract::{Path, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::error::{ApiError, ApiResult};
use crate::models::{Announcement, ItineraryStop, Trip};
use crate::state::AppState;

#[derive(Serialize)]
struct MeResponse {
    user: crate::models::AuthUser,
    trip: Trip,
}

#[derive(Serialize)]
struct HomeNow {
    trip: Trip,
    next_stop: Option<ItineraryStop>,
    latest_announcement: Option<Announcement>,
    open_count_session_id: Option<Uuid>,
}

async fn me(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<MeResponse>> {
    let trip: Trip = sqlx::query_as(
        r#"SELECT id, title, year, starts_on, ends_on, helpers_may_start_count
           FROM trips WHERE id = $1"#,
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| ApiError::NotFound("Trip not found".into()))?;

    Ok(Json(MeResponse { user, trip }))
}

async fn home_now(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<HomeNow>> {
    let trip: Trip = sqlx::query_as(
        r#"SELECT id, title, year, starts_on, ends_on, helpers_may_start_count
           FROM trips WHERE id = $1"#,
    )
    .bind(user.trip_id)
    .fetch_one(&state.db)
    .await?;

    let next_stop: Option<ItineraryStop> = sqlx::query_as(
        r#"
        SELECT id, trip_id, day_date, starts_at, title, place_name, notes, map_url,
               lost_person_tip, sort_order
        FROM itinerary_stops
        WHERE trip_id = $1 AND day_date >= CURRENT_DATE
        ORDER BY day_date, sort_order
        LIMIT 1
        "#,
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;

    let latest_announcement: Option<Announcement> = sqlx::query_as(
        r#"
        SELECT id, trip_id, author_id, priority, title, body, count_session_id, created_at
        FROM announcements
        WHERE trip_id = $1
        ORDER BY created_at DESC
        LIMIT 1
        "#,
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;

    let open_count: Option<(Uuid,)> = sqlx::query_as(
        r#"SELECT id FROM count_sessions WHERE trip_id = $1 AND status = 'open' LIMIT 1"#,
    )
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;

    Ok(Json(HomeNow {
        trip,
        next_stop,
        latest_announcement,
        open_count_session_id: open_count.map(|r| r.0),
    }))
}

async fn itinerary(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(trip_id): Path<Uuid>,
) -> ApiResult<Json<Vec<ItineraryStop>>> {
    if trip_id != user.trip_id {
        return Err(ApiError::Forbidden("Wrong trip".into()));
    }
    let stops: Vec<ItineraryStop> = sqlx::query_as(
        r#"
        SELECT id, trip_id, day_date, starts_at, title, place_name, notes, map_url,
               lost_person_tip, sort_order
        FROM itinerary_stops
        WHERE trip_id = $1
        ORDER BY day_date, sort_order
        "#,
    )
    .bind(trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(stops))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me", get(me))
        .route("/home/now", get(home_now))
        .route("/trips/{trip_id}/itinerary", get(itinerary))
}
