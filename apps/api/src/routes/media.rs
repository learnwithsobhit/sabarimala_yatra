use std::path::{Path, PathBuf};

use axum::body::Body;
use axum::extract::{Multipart, Path as AxumPath, Query, State};
use axum::http::{header, StatusCode};
use axum::response::Response;
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::media_sign;
use crate::state::AppState;

#[derive(Debug, FromRow)]
struct MediaDb {
    id: Uuid,
    trip_id: Uuid,
    uploader_id: Uuid,
    caption: Option<String>,
    storage_key: String,
    content_type: String,
    byte_size: i64,
    approved: bool,
    created_at: DateTime<Utc>,
    uploader_name: String,
}

#[derive(Debug, Serialize)]
struct MediaRow {
    id: Uuid,
    trip_id: Uuid,
    uploader_id: Uuid,
    caption: Option<String>,
    storage_key: String,
    content_type: String,
    byte_size: i64,
    approved: bool,
    created_at: DateTime<Utc>,
    uploader_name: String,
    url_path: String,
}

impl MediaDb {
    fn into_row(self, secret: &str) -> MediaRow {
        let url_path = media_sign::signed_url_path(secret, &self.storage_key);
        MediaRow {
            id: self.id,
            trip_id: self.trip_id,
            uploader_id: self.uploader_id,
            caption: self.caption,
            storage_key: self.storage_key,
            content_type: self.content_type,
            byte_size: self.byte_size,
            approved: self.approved,
            created_at: self.created_at,
            uploader_name: self.uploader_name,
            url_path,
        }
    }
}

#[derive(Debug, Deserialize)]
struct SignedQuery {
    exp: i64,
    sig: String,
}

const MEDIA_SELECT: &str = r#"
SELECT m.id, m.trip_id, m.uploader_id, m.caption, m.storage_key, m.content_type,
       m.byte_size, m.approved, m.created_at, u.display_name AS uploader_name
FROM media_assets m
JOIN trip_members tm ON tm.id = m.uploader_id
JOIN users u ON u.id = tm.user_id
"#;

async fn list_approved(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<MediaRow>>> {
    let rows: Vec<MediaDb> = sqlx::query_as(&format!(
        "{MEDIA_SELECT} WHERE m.trip_id = $1 AND m.approved = TRUE ORDER BY m.created_at DESC LIMIT 100"
    ))
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| r.into_row(&state.config.jwt_secret))
            .collect(),
    ))
}

async fn list_pending(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<MediaRow>>> {
    require_helper(&user)?;
    let rows: Vec<MediaDb> = sqlx::query_as(&format!(
        "{MEDIA_SELECT} WHERE m.trip_id = $1 AND m.approved = FALSE ORDER BY m.created_at DESC LIMIT 100"
    ))
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| r.into_row(&state.config.jwt_secret))
            .collect(),
    ))
}

async fn my_uploads(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<MediaRow>>> {
    let rows: Vec<MediaDb> = sqlx::query_as(&format!(
        "{MEDIA_SELECT} WHERE m.uploader_id = $1 ORDER BY m.created_at DESC LIMIT 50"
    ))
    .bind(user.member_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| r.into_row(&state.config.jwt_secret))
            .collect(),
    ))
}

async fn serve_signed(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
) -> Result<Response, ApiError> {
    // Prevent path traversal
    if key.contains("..") || key.starts_with('/') {
        return Err(ApiError::Forbidden("Invalid path".into()));
    }
    if !media_sign::verify(&state.config.jwt_secret, &key, q.exp, &q.sig) {
        return Err(ApiError::Unauthorized("Invalid or expired media link".into()));
    }
    let path = PathBuf::from(&state.config.upload_dir).join(&key);
    let data = fs::read(&path)
        .await
        .map_err(|_| ApiError::NotFound("File not found".into()))?;
    let ct = match path.extension().and_then(|e| e.to_str()) {
        Some("png") => "image/png",
        Some("webp") => "image/webp",
        Some("gif") => "image/gif",
        _ => "image/jpeg",
    };
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, ct)
        .header(header::CACHE_CONTROL, "private, max-age=3600")
        .body(Body::from(data))
        .map_err(|e| ApiError::Internal(e.into()))?)
}

async fn upload(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    mut multipart: Multipart,
) -> ApiResult<Json<MediaRow>> {
    let mut caption: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut content_type = "image/jpeg".to_string();
    let mut original_name = "photo.jpg".to_string();

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| ApiError::BadRequest(format!("multipart: {e}")))?
    {
        let name = field.name().unwrap_or("").to_string();
        if name == "caption" {
            caption = Some(
                field
                    .text()
                    .await
                    .map_err(|e| ApiError::BadRequest(e.to_string()))?,
            );
        } else if name == "file" {
            if let Some(ct) = field.content_type() {
                content_type = ct.to_string();
            }
            if let Some(fname) = field.file_name() {
                original_name = fname.to_string();
            }
            let data = field
                .bytes()
                .await
                .map_err(|e| ApiError::BadRequest(e.to_string()))?;
            if data.len() > 8 * 1024 * 1024 {
                return Err(ApiError::BadRequest("Image must be under 8MB".into()));
            }
            if !content_type.starts_with("image/") {
                return Err(ApiError::BadRequest("Only image uploads are allowed".into()));
            }
            file_bytes = Some(data.to_vec());
        }
    }

    let data = file_bytes.ok_or_else(|| ApiError::BadRequest("file field required".into()))?;
    let ext = Path::new(&original_name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("jpg");
    let key = format!("{}/{}.{}", user.trip_id, Uuid::new_v4(), ext);
    let full = PathBuf::from(&state.config.upload_dir).join(&key);
    if let Some(parent) = full.parent() {
        fs::create_dir_all(parent)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    }
    let mut f = fs::File::create(&full)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    f.write_all(&data)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let auto_approve = user.role.can_help_mark();
    let id = Uuid::new_v4();

    if auto_approve {
        sqlx::query(
            r#"
            INSERT INTO media_assets
                (id, trip_id, uploader_id, caption, storage_key, content_type, byte_size, approved, approved_by, approved_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE, $3, NOW())
            "#,
        )
        .bind(id)
        .bind(user.trip_id)
        .bind(user.member_id)
        .bind(caption.as_deref().map(str::trim).filter(|s| !s.is_empty()))
        .bind(&key)
        .bind(&content_type)
        .bind(data.len() as i64)
        .execute(&state.db)
        .await?;
    } else {
        sqlx::query(
            r#"
            INSERT INTO media_assets
                (id, trip_id, uploader_id, caption, storage_key, content_type, byte_size, approved)
            VALUES ($1, $2, $3, $4, $5, $6, $7, FALSE)
            "#,
        )
        .bind(id)
        .bind(user.trip_id)
        .bind(user.member_id)
        .bind(caption.as_deref().map(str::trim).filter(|s| !s.is_empty()))
        .bind(&key)
        .bind(&content_type)
        .bind(data.len() as i64)
        .execute(&state.db)
        .await?;
    }

    let row: MediaDb = sqlx::query_as(&format!("{MEDIA_SELECT} WHERE m.id = $1"))
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(row.into_row(&state.config.jwt_secret)))
}

async fn approve(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    AxumPath(media_id): AxumPath<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;
    let n = sqlx::query(
        r#"
        UPDATE media_assets
        SET approved = TRUE, approved_by = $2, approved_at = NOW()
        WHERE id = $1 AND trip_id = $3
        "#,
    )
    .bind(media_id)
    .bind(user.member_id)
    .bind(user.trip_id)
    .execute(&state.db)
    .await?
    .rows_affected();

    if n == 0 {
        return Err(ApiError::NotFound("Media not found".into()));
    }
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn reject(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    AxumPath(media_id): AxumPath<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    require_helper(&user)?;
    let key: Option<(String,)> = sqlx::query_as(
        "SELECT storage_key FROM media_assets WHERE id = $1 AND trip_id = $2 AND approved = FALSE",
    )
    .bind(media_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;

    let Some((storage_key,)) = key else {
        return Err(ApiError::NotFound("Pending media not found".into()));
    };

    sqlx::query("DELETE FROM media_assets WHERE id = $1")
        .bind(media_id)
        .execute(&state.db)
        .await?;

    let path = PathBuf::from(&state.config.upload_dir).join(&storage_key);
    let _ = fs::remove_file(path).await;

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/media", get(list_approved).post(upload))
        .route("/media/mine", get(my_uploads))
        .route("/media/pending", get(list_pending))
        .route("/media/{media_id}/approve", post(approve))
        .route("/media/{media_id}/reject", post(reject))
        // Nested path after trip_id/uuid.ext — use wildcard
        .route("/media/files/{*key}", get(serve_signed))
}
