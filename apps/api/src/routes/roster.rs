use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::error::{ApiError, ApiResult};
use crate::models::{MemberRole, TripMemberRow};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct RosterImportBody {
    /// CSV text: phone,name,role[,kanni,senior]
    pub csv: String,
}

async fn list_members(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<TripMemberRow>>> {
    let rows: Vec<TripMemberRow> = sqlx::query_as(
        r#"
        SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
               u.display_name, u.phone_e164, tm.is_active
        FROM trip_members tm
        JOIN users u ON u.id = tm.user_id
        WHERE tm.trip_id = $1
        ORDER BY u.display_name
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

fn parse_role(s: &str) -> ApiResult<MemberRole> {
    match s.trim().to_ascii_lowercase().as_str() {
        "leader" => Ok(MemberRole::Leader),
        "volunteer" => Ok(MemberRole::Volunteer),
        "swamy" | "" => Ok(MemberRole::Swamy),
        other => Err(ApiError::BadRequest(format!("Unknown role: {other}"))),
    }
}

fn normalize_phone(raw: &str) -> String {
    let digits: String = raw.chars().filter(|c| c.is_ascii_digit() || *c == '+').collect();
    if digits.starts_with('+') {
        digits
    } else if digits.len() == 10 {
        format!("+91{digits}")
    } else {
        format!("+{digits}")
    }
}

async fn import_roster(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<RosterImportBody>,
) -> ApiResult<Json<serde_json::Value>> {
    if user.role != MemberRole::Leader {
        return Err(ApiError::Forbidden("Only leader can import roster".into()));
    }

    let mut rdr = csv::ReaderBuilder::new()
        .flexible(true)
        .has_headers(true)
        .from_reader(body.csv.as_bytes());

    let mut imported = 0u32;
    for result in rdr.records() {
        let record = result.map_err(|e| ApiError::BadRequest(e.to_string()))?;
        if record.is_empty() {
            continue;
        }
        let phone = normalize_phone(record.get(0).unwrap_or("").trim());
        let name = record.get(1).unwrap_or("").trim();
        if phone.len() < 10 || name.is_empty() {
            continue;
        }
        let role = parse_role(record.get(2).unwrap_or("swamy"))?;
        let kanni = record
            .get(3)
            .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false);
        let senior = record
            .get(4)
            .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false);

        let user_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO users (phone_e164, display_name)
            VALUES ($1, $2)
            ON CONFLICT (phone_e164) DO UPDATE SET display_name = EXCLUDED.display_name
            RETURNING id
            "#,
        )
        .bind(&phone)
        .bind(name)
        .fetch_one(&state.db)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO trip_members (trip_id, user_id, role, is_kanni, is_senior)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (trip_id, user_id) DO UPDATE
              SET role = EXCLUDED.role,
                  is_kanni = EXCLUDED.is_kanni,
                  is_senior = EXCLUDED.is_senior,
                  is_active = TRUE
            "#,
        )
        .bind(user.trip_id)
        .bind(user_id)
        .bind(role)
        .bind(kanni)
        .bind(senior)
        .execute(&state.db)
        .await?;

        imported += 1;
    }

    Ok(Json(serde_json::json!({ "imported": imported })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/roster", get(list_members).post(import_roster))
}
