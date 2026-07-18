use axum::extract::FromRequestParts;
use axum::http::request::Parts;

use crate::auth::jwt::decode_token;
use crate::error::{ApiError, ApiResult};
use crate::models::AuthUser;
use crate::state::AppState;

pub struct AuthUserExt(pub AuthUser);

impl FromRequestParts<AppState> for AuthUserExt {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| ApiError::Unauthorized("Missing Authorization header".into()))?;

        let token = auth
            .strip_prefix("Bearer ")
            .ok_or_else(|| ApiError::Unauthorized("Expected Bearer token".into()))?;

        let claims = decode_token(&state.config.jwt_secret, token)?;
        Ok(AuthUserExt(AuthUser {
            user_id: claims.sub,
            member_id: claims.member_id,
            trip_id: claims.trip_id,
            role: claims.role,
            display_name: claims.name,
            phone_e164: claims.phone,
        }))
    }
}

pub fn require_helper(user: &AuthUser) -> ApiResult<()> {
    if user.role.can_help_mark() {
        Ok(())
    } else {
        Err(ApiError::Forbidden(
            "Only leader or volunteer can perform this action".into(),
        ))
    }
}
