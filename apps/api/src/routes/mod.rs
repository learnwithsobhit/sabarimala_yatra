mod announcements;
mod assignments;
mod auth_routes;
mod chat;
mod count;
mod devices;
mod expenses;
mod food;
mod health;
mod media;
mod packing;
mod roster;
mod trip;

use axum::Router;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .merge(health::router())
        .merge(auth_routes::router())
        .merge(trip::router())
        .merge(roster::router())
        .merge(count::router())
        .merge(announcements::router())
        .merge(assignments::router())
        .merge(expenses::router())
        .merge(chat::router())
        .merge(devices::router())
        .merge(food::router())
        .merge(packing::router())
        .merge(media::router())
}
