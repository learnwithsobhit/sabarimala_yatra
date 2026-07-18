use axum::extract::{Path, State};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::error::{ApiError, ApiResult};
use crate::media_store::PresignedUpload;
use crate::models::{MemberRole, TripMemberRow};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct RosterImportBody {
    /// CSV text: phone,name,role[,kanni,senior,years]
    pub csv: String,
}

/// Roster row enriched with the derived Swamy tag.
#[derive(Debug, Serialize)]
struct RosterMemberOut {
    id: Uuid,
    trip_id: Uuid,
    user_id: Uuid,
    role: MemberRole,
    is_kanni: bool,
    is_senior: bool,
    display_name: String,
    phone_e164: String,
    is_active: bool,
    yatra_years: Option<i32>,
    photo_url: Option<String>,
    /// Derived from `yatra_years` (falls back to `is_kanni`): Kanni / Bell / N-year Swamy.
    tag: Option<String>,
}

impl RosterMemberOut {
    fn from_row(r: TripMemberRow) -> Self {
        let tag = swamy_tag(r.yatra_years, r.is_kanni);
        Self {
            id: r.id,
            trip_id: r.trip_id,
            user_id: r.user_id,
            role: r.role,
            is_kanni: r.is_kanni,
            is_senior: r.is_senior,
            display_name: r.display_name,
            phone_e164: r.phone_e164,
            is_active: r.is_active,
            yatra_years: r.yatra_years,
            photo_url: r.photo_url,
            tag,
        }
    }
}

/// Year-count -> Swamy tag. 1 = Kanni, 3 = Bell, otherwise "N-year Swamy".
/// When the count is unknown, fall back to the legacy `is_kanni` flag.
fn swamy_tag(years: Option<i32>, is_kanni: bool) -> Option<String> {
    match years {
        Some(1) => Some("Kanni Swamy".to_string()),
        Some(3) => Some("Bell Swamy".to_string()),
        Some(n) if n >= 2 => Some(format!("{n}-year Swamy")),
        Some(_) => None,
        None => {
            if is_kanni {
                Some("Kanni Swamy".to_string())
            } else {
                None
            }
        }
    }
}

const MEMBER_SELECT: &str = r#"
    SELECT tm.id, tm.trip_id, tm.user_id, tm.role, tm.is_kanni, tm.is_senior,
           u.display_name, u.phone_e164, tm.is_active, tm.yatra_years, tm.photo_url
    FROM trip_members tm
    JOIN users u ON u.id = tm.user_id
"#;

async fn list_members(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<RosterMemberOut>>> {
    let rows: Vec<TripMemberRow> = sqlx::query_as(&format!(
        "{MEMBER_SELECT} WHERE tm.trip_id = $1 ORDER BY u.display_name"
    ))
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.into_iter().map(RosterMemberOut::from_row).collect()))
}

fn require_leader(user: &crate::models::AuthUser) -> ApiResult<()> {
    if user.role != MemberRole::Leader {
        return Err(ApiError::Forbidden("Only leader can manage the roster".into()));
    }
    Ok(())
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

/// Only image content types are allowed for yatri photos.
fn image_ext(ct: &str) -> ApiResult<&'static str> {
    let ct = ct.split(';').next().unwrap_or("").trim().to_ascii_lowercase();
    match ct.as_str() {
        "image/jpeg" | "image/jpg" => Ok("jpg"),
        "image/png" => Ok("png"),
        "image/webp" => Ok("webp"),
        "image/heic" | "image/heif" => Ok("heic"),
        _ => Err(ApiError::BadRequest(
            "Only image uploads are allowed for photos".into(),
        )),
    }
}

#[derive(Debug, Deserialize)]
pub struct PhotoPresignReq {
    content_type: String,
}

/// Request a presigned upload target for a yatri photo (`yatris/<trip>/…`).
async fn photo_presign(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(req): Json<PhotoPresignReq>,
) -> ApiResult<Json<PresignedUpload>> {
    require_leader(&user)?;
    let ext = image_ext(&req.content_type)?;
    let key = state.media.build_yatri_key(user.trip_id, ext);
    let signed = state.media.presign_put(&key, req.content_type.trim())?;
    Ok(Json(signed))
}

#[derive(Debug, Deserialize)]
pub struct UpsertMember {
    pub phone: String,
    pub display_name: String,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub yatra_years: Option<i32>,
    #[serde(default)]
    pub is_senior: Option<bool>,
    /// Storage key returned by `/roster/photo/presign` (client already PUT the bytes).
    #[serde(default)]
    pub photo_key: Option<String>,
    /// Optional pre-computed public URL; server prefers `photo_key` when present.
    #[serde(default)]
    pub photo_url: Option<String>,
}

/// Resolve the photo URL from an uploaded key (clearing its unconfirmed tag),
/// or fall back to a client-provided URL.
async fn resolve_photo_url(
    state: &AppState,
    trip_id: Uuid,
    photo_key: &Option<String>,
    photo_url: &Option<String>,
) -> ApiResult<Option<String>> {
    if let Some(key) = photo_key.as_deref().filter(|k| !k.trim().is_empty()) {
        if !state.media.yatri_key_belongs_to_trip(key, trip_id) {
            return Err(ApiError::Forbidden("Invalid photo key".into()));
        }
        // Best-effort: keep the object past the orphan-cleanup lifecycle rule.
        if let Err(e) = state.media.mark_confirmed(key).await {
            tracing::warn!(error = %e, key, "failed to confirm yatri photo (non-fatal)");
        }
        return Ok(Some(state.media.read_url(key)));
    }
    Ok(photo_url
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string()))
}

async fn fetch_member(state: &AppState, member_id: Uuid) -> ApiResult<RosterMemberOut> {
    let row: TripMemberRow = sqlx::query_as(&format!("{MEMBER_SELECT} WHERE tm.id = $1"))
        .bind(member_id)
        .fetch_one(&state.db)
        .await?;
    Ok(RosterMemberOut::from_row(row))
}

/// Leader: add (or upsert by phone) a single yatri with photo + years.
async fn add_member(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<UpsertMember>,
) -> ApiResult<Json<RosterMemberOut>> {
    require_leader(&user)?;
    let phone = normalize_phone(body.phone.trim());
    let name = body.display_name.trim();
    if phone.len() < 10 || name.is_empty() {
        return Err(ApiError::BadRequest("phone and name are required".into()));
    }
    let role = parse_role(body.role.as_deref().unwrap_or("swamy"))?;
    let kanni = matches!(body.yatra_years, Some(1));
    let senior = body.is_senior.unwrap_or(false);
    let photo_url = resolve_photo_url(&state, user.trip_id, &body.photo_key, &body.photo_url).await?;

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

    let member_id: Uuid = sqlx::query_scalar(
        r#"
        INSERT INTO trip_members (trip_id, user_id, role, is_kanni, is_senior, yatra_years, photo_url)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (trip_id, user_id) DO UPDATE
          SET role = EXCLUDED.role,
              is_kanni = EXCLUDED.is_kanni,
              is_senior = EXCLUDED.is_senior,
              yatra_years = EXCLUDED.yatra_years,
              photo_url = COALESCE(EXCLUDED.photo_url, trip_members.photo_url),
              is_active = TRUE
        RETURNING id
        "#,
    )
    .bind(user.trip_id)
    .bind(user_id)
    .bind(role)
    .bind(kanni)
    .bind(senior)
    .bind(body.yatra_years)
    .bind(&photo_url)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(fetch_member(&state, member_id).await?))
}

/// Leader: edit an existing member (name, phone, role, years, photo).
async fn update_member(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Path(member_id): Path<Uuid>,
    Json(body): Json<UpsertMember>,
) -> ApiResult<Json<RosterMemberOut>> {
    require_leader(&user)?;

    let existing: Option<(Uuid,)> =
        sqlx::query_as("SELECT user_id FROM trip_members WHERE id = $1 AND trip_id = $2")
            .bind(member_id)
            .bind(user.trip_id)
            .fetch_optional(&state.db)
            .await?;
    let Some((user_id,)) = existing else {
        return Err(ApiError::NotFound("Member not found on this trip".into()));
    };

    let phone = normalize_phone(body.phone.trim());
    let name = body.display_name.trim();
    if phone.len() < 10 || name.is_empty() {
        return Err(ApiError::BadRequest("phone and name are required".into()));
    }
    let role = parse_role(body.role.as_deref().unwrap_or("swamy"))?;
    let kanni = matches!(body.yatra_years, Some(1));
    let senior = body.is_senior.unwrap_or(false);
    let photo_url = resolve_photo_url(&state, user.trip_id, &body.photo_key, &body.photo_url).await?;

    sqlx::query(
        r#"UPDATE users SET display_name = $1, phone_e164 = $2, updated_at = NOW() WHERE id = $3"#,
    )
    .bind(name)
    .bind(&phone)
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(|e| {
        if e.to_string().contains("users_phone_e164_key") {
            ApiError::BadRequest("Another member already uses that phone number".into())
        } else {
            ApiError::from(e)
        }
    })?;

    sqlx::query(
        r#"
        UPDATE trip_members
        SET role = $1,
            is_kanni = $2,
            is_senior = $3,
            yatra_years = $4,
            photo_url = COALESCE($5, photo_url)
        WHERE id = $6
        "#,
    )
    .bind(role)
    .bind(kanni)
    .bind(senior)
    .bind(body.yatra_years)
    .bind(&photo_url)
    .bind(member_id)
    .execute(&state.db)
    .await?;

    Ok(Json(fetch_member(&state, member_id).await?))
}

async fn import_roster(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<RosterImportBody>,
) -> ApiResult<Json<serde_json::Value>> {
    require_leader(&user)?;

    let mut rdr = csv::ReaderBuilder::new()
        .flexible(true)
        // Treat every line as data. A header line like `phone,name,...` is
        // skipped by the phone-length guard below, so we never silently drop
        // the first real row when a leader pastes rows without a header.
        .has_headers(false)
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
        // Be lenient: an unknown role in one row shouldn't fail the whole import.
        let role = parse_role(record.get(2).unwrap_or("swamy")).unwrap_or(MemberRole::Swamy);
        let years: Option<i32> = record
            .get(5)
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .and_then(|v| v.parse::<i32>().ok());
        let kanni = record
            .get(3)
            .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false)
            || matches!(years, Some(1));
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
            INSERT INTO trip_members (trip_id, user_id, role, is_kanni, is_senior, yatra_years)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (trip_id, user_id) DO UPDATE
              SET role = EXCLUDED.role,
                  is_kanni = EXCLUDED.is_kanni,
                  is_senior = EXCLUDED.is_senior,
                  yatra_years = EXCLUDED.yatra_years,
                  is_active = TRUE
            "#,
        )
        .bind(user.trip_id)
        .bind(user_id)
        .bind(role)
        .bind(kanni)
        .bind(senior)
        .bind(years)
        .execute(&state.db)
        .await?;

        imported += 1;
    }

    Ok(Json(serde_json::json!({ "imported": imported })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/roster", get(list_members).post(import_roster))
        .route("/roster/photo/presign", post(photo_presign))
        .route("/roster/member", post(add_member))
        .route("/roster/member/{member_id}", put(update_member))
}
