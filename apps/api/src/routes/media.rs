use std::path::PathBuf;

use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, Multipart, Path as AxumPath, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::{get, post, put};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tokio::fs;
use uuid::Uuid;

use crate::auth::middleware::require_helper;
use crate::auth::AuthUserExt;
use crate::error::{ApiError, ApiResult};
use crate::media_sign;
use crate::media_store::PresignedUpload;
use crate::state::AppState;

/// Max size for uploads that transit the API (local blob + multipart fallback).
const MAX_UPLOAD_BYTES: usize = 256 * 1024 * 1024;
/// Photos over the API are kept small; video should use the presign flow.
const MAX_IMAGE_BYTES: usize = 12 * 1024 * 1024;

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
    public_url: Option<String>,
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
    is_video: bool,
    created_at: DateTime<Utc>,
    uploader_name: String,
    url_path: String,
}

impl MediaDb {
    fn into_row(self, state: &AppState) -> MediaRow {
        // Prefer the persisted (S3/CloudFront) URL; fall back to a freshly
        // derived signed path (local dev, or legacy rows without a stored URL).
        let url_path = self
            .public_url
            .clone()
            .filter(|u| !u.trim().is_empty())
            .unwrap_or_else(|| state.media.read_url(&self.storage_key));
        let is_video = self.content_type.starts_with("video/");
        MediaRow {
            id: self.id,
            trip_id: self.trip_id,
            uploader_id: self.uploader_id,
            caption: self.caption,
            storage_key: self.storage_key,
            content_type: self.content_type,
            byte_size: self.byte_size,
            approved: self.approved,
            is_video,
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
       m.byte_size, m.approved, m.created_at, u.display_name AS uploader_name,
       m.public_url
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
    Ok(Json(rows.into_iter().map(|r| r.into_row(&state)).collect()))
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
    Ok(Json(rows.into_iter().map(|r| r.into_row(&state)).collect()))
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
    Ok(Json(rows.into_iter().map(|r| r.into_row(&state)).collect()))
}

/// Validate a client-provided content type and return the file extension to use.
fn ext_for_content_type(ct: &str) -> ApiResult<&'static str> {
    let ct = ct.split(';').next().unwrap_or("").trim().to_ascii_lowercase();
    match ct.as_str() {
        "image/jpeg" | "image/jpg" => Ok("jpg"),
        "image/png" => Ok("png"),
        "image/webp" => Ok("webp"),
        "image/gif" => Ok("gif"),
        "image/heic" | "image/heif" => Ok("heic"),
        "video/mp4" => Ok("mp4"),
        "video/quicktime" => Ok("mov"),
        "video/x-matroska" => Ok("mkv"),
        "video/webm" => Ok("webm"),
        "video/3gpp" => Ok("3gp"),
        _ => Err(ApiError::BadRequest(
            "Only image or video uploads are allowed".into(),
        )),
    }
}

#[derive(Debug, Deserialize)]
struct PresignRequest {
    content_type: String,
}

/// Step 1: request a presigned upload target for a photo or video.
async fn presign(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(req): Json<PresignRequest>,
) -> ApiResult<Json<PresignedUpload>> {
    let ext = ext_for_content_type(&req.content_type)?;
    let key = state.media.build_key(user.trip_id, ext);
    let signed = state.media.presign_put(&key, req.content_type.trim())?;
    Ok(Json(signed))
}

#[derive(Debug, Deserialize)]
struct ConfirmRequest {
    key: String,
    content_type: String,
    #[serde(default)]
    byte_size: i64,
    #[serde(default)]
    caption: Option<String>,
}

/// Step 3: persist a media row after the client PUT the bytes to storage.
async fn confirm(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(req): Json<ConfirmRequest>,
) -> ApiResult<Json<MediaRow>> {
    // Guard: the client can only confirm keys under its own trip prefix.
    if !state.media.key_belongs_to_trip(&req.key, user.trip_id) {
        return Err(ApiError::Forbidden("Invalid storage key".into()));
    }
    // Validate the declared content type.
    let _ = ext_for_content_type(&req.content_type)?;
    let byte_size = req.byte_size.max(0);
    let caption = req
        .caption
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    let row = insert_media(
        &state,
        user.trip_id,
        user.member_id,
        user.role.can_help_mark(),
        caption.as_deref(),
        &req.key,
        req.content_type.trim(),
        byte_size,
    )
    .await?;

    // Clear the orphan-cleanup tag now that the object is referenced. Failure is
    // logged but does not fail the request (the row is already persisted).
    if let Err(e) = state.media.mark_confirmed(&req.key).await {
        tracing::warn!(error = %e, key = %req.key, "could not clear unconfirmed tag");
    }

    Ok(Json(row))
}

/// Local-dev only: receive the raw bytes for a presigned local upload.
async fn blob_put(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult<Json<serde_json::Value>> {
    if state.media.is_s3() {
        return Err(ApiError::BadRequest(
            "Direct blob upload is disabled when S3 is configured".into(),
        ));
    }
    if key.contains("..") || key.starts_with('/') {
        return Err(ApiError::Forbidden("Invalid path".into()));
    }
    if !media_sign::verify(&state.config.jwt_secret, &key, q.exp, &q.sig) {
        return Err(ApiError::Unauthorized("Invalid or expired upload link".into()));
    }
    if body.len() > MAX_UPLOAD_BYTES {
        return Err(ApiError::BadRequest("Upload too large".into()));
    }
    let content_type = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream");
    state.media.put_bytes(&key, &body, content_type).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn serve_signed(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
) -> Result<Response, ApiError> {
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
        Some("heic") => "image/heic",
        Some("mp4") => "video/mp4",
        Some("mov") => "video/quicktime",
        Some("mkv") => "video/x-matroska",
        Some("webm") => "video/webm",
        Some("3gp") => "video/3gpp",
        _ => "image/jpeg",
    };
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, ct)
        .header(header::CACHE_CONTROL, "private, max-age=3600")
        .body(Body::from(data))
        .map_err(|e| ApiError::Internal(e.into()))?)
}

/// Fallback multipart upload (photos). Routes bytes through the store so it
/// works for both local disk and S3. Prefer the presign flow for video.
async fn upload(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    mut multipart: Multipart,
) -> ApiResult<Json<MediaRow>> {
    let mut caption: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut content_type = "image/jpeg".to_string();

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
            let data = field
                .bytes()
                .await
                .map_err(|e| ApiError::BadRequest(e.to_string()))?;
            if content_type.starts_with("image/") && data.len() > MAX_IMAGE_BYTES {
                return Err(ApiError::BadRequest("Image must be under 12MB".into()));
            }
            if data.len() > MAX_UPLOAD_BYTES {
                return Err(ApiError::BadRequest("Upload too large".into()));
            }
            file_bytes = Some(data.to_vec());
        }
    }

    let data = file_bytes.ok_or_else(|| ApiError::BadRequest("file field required".into()))?;
    let ext = ext_for_content_type(&content_type)?;
    let key = state.media.build_key(user.trip_id, ext);
    state
        .media
        .put_bytes(&key, &data, content_type.trim())
        .await?;

    let caption = caption
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    let row = insert_media(
        &state,
        user.trip_id,
        user.member_id,
        user.role.can_help_mark(),
        caption.as_deref(),
        &key,
        content_type.trim(),
        data.len() as i64,
    )
    .await?;
    Ok(Json(row))
}

#[allow(clippy::too_many_arguments)]
async fn insert_media(
    state: &AppState,
    trip_id: Uuid,
    uploader_id: Uuid,
    auto_approve: bool,
    caption: Option<&str>,
    key: &str,
    content_type: &str,
    byte_size: i64,
) -> ApiResult<MediaRow> {
    let id = Uuid::new_v4();
    // Persist the stable public URL for S3 (the file lives only in S3). For the
    // local backend the read URL is a short-lived signed path, so store NULL and
    // derive it per request instead.
    let public_url = if state.media.is_s3() {
        Some(state.media.read_url(key))
    } else {
        None
    };
    if auto_approve {
        sqlx::query(
            r#"
            INSERT INTO media_assets
                (id, trip_id, uploader_id, caption, storage_key, content_type, byte_size, public_url, approved, approved_by, approved_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TRUE, $3, NOW())
            "#,
        )
        .bind(id)
        .bind(trip_id)
        .bind(uploader_id)
        .bind(caption)
        .bind(key)
        .bind(content_type)
        .bind(byte_size)
        .bind(public_url.as_deref())
        .execute(&state.db)
        .await?;
    } else {
        sqlx::query(
            r#"
            INSERT INTO media_assets
                (id, trip_id, uploader_id, caption, storage_key, content_type, byte_size, public_url, approved)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, FALSE)
            "#,
        )
        .bind(id)
        .bind(trip_id)
        .bind(uploader_id)
        .bind(caption)
        .bind(key)
        .bind(content_type)
        .bind(byte_size)
        .bind(public_url.as_deref())
        .execute(&state.db)
        .await?;
    }

    let row: MediaDb = sqlx::query_as(&format!("{MEDIA_SELECT} WHERE m.id = $1"))
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    Ok(row.into_row(state))
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

    let _ = state.media.delete(&storage_key).await;

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub fn router() -> Router<AppState> {
    // Routes that may receive large bodies (local dev uploads / multipart).
    let large = Router::new()
        .route("/media", post(upload))
        .route("/media/blob/{*key}", put(blob_put))
        .layer(DefaultBodyLimit::max(MAX_UPLOAD_BYTES));

    Router::new()
        .route("/media", get(list_approved))
        .route("/media/mine", get(my_uploads))
        .route("/media/pending", get(list_pending))
        .route("/media/presign", post(presign))
        .route("/media/confirm", post(confirm))
        .route("/media/{media_id}/approve", post(approve))
        .route("/media/{media_id}/reject", post(reject))
        .route("/media/files/{*key}", get(serve_signed))
        .merge(large)
}
