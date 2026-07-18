use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::state::AppState;

#[derive(Serialize)]
struct Health {
    status: &'static str,
    service: &'static str,
    database: &'static str,
}

async fn health(State(state): State<AppState>) -> (StatusCode, Json<Health>) {
    let db_ok = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.db)
        .await
        .is_ok();
    let status = if db_ok {
        (
            StatusCode::OK,
            Health {
                status: "ok",
                service: "swamy_sharanam_api",
                database: "up",
            },
        )
    } else {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Health {
                status: "degraded",
                service: "swamy_sharanam_api",
                database: "down",
            },
        )
    };
    (status.0, Json(status.1))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/health", get(health))
}
