use axum::extract::FromRequestParts;
use axum::http::request::Parts;

use crate::auth::jwt::decode_token;
use crate::error::{ApiError, ApiResult};
use crate::models::{AuthUser, MemberRole};
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
        let membership: Option<(MemberRole, bool, String, String)> = sqlx::query_as(
            r#"
            SELECT tm.role, tm.is_active, u.display_name, u.phone_e164
            FROM trip_members tm
            JOIN users u ON u.id = tm.user_id
            WHERE tm.id = $1 AND tm.trip_id = $2 AND tm.user_id = $3
            "#,
        )
        .bind(claims.member_id)
        .bind(claims.trip_id)
        .bind(claims.sub)
        .fetch_optional(&state.db)
        .await?;

        let Some((role, is_active, display_name, phone_e164)) = membership else {
            return Err(ApiError::Unauthorized(
                "Session is no longer valid for this trip".into(),
            ));
        };
        if !is_active {
            return Err(ApiError::Forbidden(
                "This membership is inactive. Ask the leader to restore access.".into(),
            ));
        }

        Ok(AuthUserExt(AuthUser {
            user_id: claims.sub,
            member_id: claims.member_id,
            trip_id: claims.trip_id,
            role,
            display_name,
            phone_e164,
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
