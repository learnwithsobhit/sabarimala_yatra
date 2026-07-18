use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};

use crate::auth::otp::{
    AuthResponse, OtpRequest, OtpRequestResponse, OtpVerify, request_otp, verify_otp,
};
use crate::error::ApiResult;
use crate::state::AppState;

async fn otp_request(
    State(state): State<AppState>,
    Json(body): Json<OtpRequest>,
) -> ApiResult<Json<OtpRequestResponse>> {
    let resp = request_otp(&state.db, &state.config, &body.phone).await?;
    Ok(Json(resp))
}

async fn otp_verify(
    State(state): State<AppState>,
    Json(body): Json<OtpVerify>,
) -> ApiResult<Json<AuthResponse>> {
    let resp = verify_otp(
        &state.db,
        &state.config,
        &body.phone,
        &body.code,
        body.trip_id,
    )
    .await?;
    Ok(Json(resp))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/otp/request", post(otp_request))
        .route("/auth/otp/verify", post(otp_verify))
}
