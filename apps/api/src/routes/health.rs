use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::state::AppState;

#[derive(Serialize)]
struct Health {
    status: &'static str,
    service: &'static str,
}

async fn health() -> Json<Health> {
    Json(Health {
        status: "ok",
        service: "swamy_sharanam_api",
    })
}

pub fn router() -> Router<AppState> {
    Router::new().route("/health", get(health))
}
