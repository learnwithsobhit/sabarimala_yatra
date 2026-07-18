//! Pluggable media storage: local disk (dev) or S3 / CloudFront (prod).
//!
//! Uploads use presigned `PUT` so large files (video) go straight to S3 and
//! never transit the API. Reads are served from a public CloudFront/S3 base
//! URL. Local dev keeps the previous signed-path behaviour via `/media/blob`
//! (upload) and `/media/files` (download) so the mobile client uses one flow.

use std::collections::BTreeMap;
use std::path::PathBuf;

use chrono::Utc;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::config::Config;
use crate::error::{ApiError, ApiResult};
use crate::media_sign;
use crate::s3_presign::{
    encode_s3_object_path, path_style_object_path, presign_delete_url, presign_put_url,
};

const PRESIGN_TTL_SECS: u64 = 900;
/// Objects are tagged with this until `POST /media/confirm` clears the tag.
/// An S3 lifecycle rule expires still-tagged (orphaned) uploads — see
/// docs/media-s3-setup.md.
const UNCONFIRMED_TAG: &str = "state=unconfirmed";

#[derive(Clone, Debug)]
pub struct S3Config {
    pub bucket: String,
    pub region: String,
    pub access_key: String,
    pub secret_key: String,
    /// Custom S3-compatible endpoint (e.g. MinIO). `None` => real AWS S3.
    pub endpoint: Option<String>,
    /// Public read base (CloudFront or S3 URL), no trailing slash.
    pub public_base: String,
}

#[derive(Clone)]
pub enum MediaStore {
    Local {
        upload_dir: String,
        jwt_secret: String,
    },
    S3 {
        cfg: S3Config,
    },
}

/// What the client needs to upload one object and the URL to persist for reads.
#[derive(Debug, serde::Serialize)]
pub struct PresignedUpload {
    pub method: String,
    /// Absolute URL for S3, or an API-relative path for local dev.
    pub upload_url: String,
    /// Headers the client MUST send verbatim on the upload request.
    pub headers: BTreeMap<String, String>,
    pub key: String,
    pub public_url: String,
    pub expires_in_sec: i64,
}

impl MediaStore {
    pub fn from_config(config: &Config) -> ApiResult<Self> {
        if config.media_backend.eq_ignore_ascii_case("s3") {
            let cfg = S3Config {
                bucket: require(&config.s3_bucket, "S3_BUCKET")?,
                region: config
                    .aws_region
                    .clone()
                    .unwrap_or_else(|| "us-east-1".to_string()),
                access_key: require(&config.aws_access_key_id, "AWS_ACCESS_KEY_ID")?,
                secret_key: require(&config.aws_secret_access_key, "AWS_SECRET_ACCESS_KEY")?,
                endpoint: config.s3_endpoint.clone(),
                public_base: config
                    .media_public_base_url
                    .clone()
                    .map(|b| b.trim_end_matches('/').to_string())
                    .ok_or_else(|| {
                        ApiError::Internal(anyhow::anyhow!(
                            "MEDIA_PUBLIC_BASE_URL (or S3_PUBLIC_URL) is required for MEDIA_BACKEND=s3"
                        ))
                    })?,
            };
            Ok(MediaStore::S3 { cfg })
        } else {
            Ok(MediaStore::Local {
                upload_dir: config.upload_dir.clone(),
                jwt_secret: config.jwt_secret.clone(),
            })
        }
    }

    pub fn is_s3(&self) -> bool {
        matches!(self, MediaStore::S3 { .. })
    }

    /// Build a namespaced object key: `media/{trip}/{uuid}.{ext}`.
    pub fn build_key(&self, trip_id: Uuid, ext: &str) -> String {
        let ext = sanitize_ext(ext);
        format!("media/{}/{}.{}", trip_id, Uuid::new_v4(), ext)
    }

    /// Build a yatri-photo object key: `yatris/{trip}/{uuid}.{ext}`.
    pub fn build_yatri_key(&self, trip_id: Uuid, ext: &str) -> String {
        let ext = sanitize_ext(ext);
        format!("yatris/{}/{}.{}", trip_id, Uuid::new_v4(), ext)
    }

    /// Yatri photo keys must live under this trip's prefix (guards confirm).
    pub fn yatri_key_belongs_to_trip(&self, key: &str, trip_id: Uuid) -> bool {
        !key.contains("..") && key.starts_with(&format!("yatris/{}/", trip_id))
    }

    /// Keys must live under this trip's media prefix (guards `confirm`).
    pub fn key_belongs_to_trip(&self, key: &str, trip_id: Uuid) -> bool {
        !key.contains("..") && key.starts_with(&format!("media/{}/", trip_id))
    }

    /// Public/read URL for a stored object.
    pub fn read_url(&self, key: &str) -> String {
        match self {
            MediaStore::Local { jwt_secret, .. } => media_sign::signed_url_path(jwt_secret, key),
            MediaStore::S3 { cfg, .. } => format!("{}/{}", cfg.public_base, key),
        }
    }

    /// Presign a direct upload for the given key + content type.
    pub fn presign_put(&self, key: &str, content_type: &str) -> ApiResult<PresignedUpload> {
        let mut headers = BTreeMap::new();
        headers.insert("Content-Type".to_string(), content_type.to_string());
        match self {
            MediaStore::Local { jwt_secret, .. } => {
                let exp = Utc::now().timestamp() + PRESIGN_TTL_SECS as i64;
                let sig = media_sign::sign_path(jwt_secret, key, exp);
                Ok(PresignedUpload {
                    method: "PUT".into(),
                    upload_url: format!("/media/blob/{key}?exp={exp}&sig={sig}"),
                    headers,
                    key: key.to_string(),
                    public_url: self.read_url(key),
                    expires_in_sec: PRESIGN_TTL_SECS as i64,
                })
            }
            MediaStore::S3 { cfg, .. } => {
                let (host, uri, https) = s3_target(cfg, key)?;
                let upload_url = presign_put_url(
                    &host,
                    &uri,
                    &cfg.region,
                    &cfg.access_key,
                    &cfg.secret_key,
                    content_type,
                    None,
                    Some(UNCONFIRMED_TAG),
                    PRESIGN_TTL_SECS,
                    https,
                )
                .map_err(|e| ApiError::Internal(anyhow::anyhow!("presign put: {e}")))?;
                // Client must echo the signed tagging header on the PUT.
                headers.insert("x-amz-tagging".to_string(), UNCONFIRMED_TAG.to_string());
                Ok(PresignedUpload {
                    method: "PUT".into(),
                    upload_url,
                    headers,
                    key: key.to_string(),
                    public_url: self.read_url(key),
                    expires_in_sec: PRESIGN_TTL_SECS as i64,
                })
            }
        }
    }

    /// Server-side upload (multipart fallback / local blob write).
    pub async fn put_bytes(&self, key: &str, bytes: &[u8], content_type: &str) -> ApiResult<()> {
        match self {
            MediaStore::Local { upload_dir, .. } => {
                let full = PathBuf::from(upload_dir).join(key);
                if let Some(parent) = full.parent() {
                    fs::create_dir_all(parent)
                        .await
                        .map_err(|e| ApiError::Internal(e.into()))?;
                }
                let mut f = fs::File::create(&full)
                    .await
                    .map_err(|e| ApiError::Internal(e.into()))?;
                f.write_all(bytes)
                    .await
                    .map_err(|e| ApiError::Internal(e.into()))?;
                Ok(())
            }
            MediaStore::S3 { cfg, .. } => {
                let (host, uri, https) = s3_target(cfg, key)?;
                // Server-side uploads (multipart fallback) are persisted in the
                // same request, so they are never orphaned — no tag needed.
                let url = presign_put_url(
                    &host,
                    &uri,
                    &cfg.region,
                    &cfg.access_key,
                    &cfg.secret_key,
                    content_type,
                    None,
                    None,
                    PRESIGN_TTL_SECS,
                    https,
                )
                .map_err(|e| ApiError::Internal(anyhow::anyhow!("presign put: {e}")))?;
                let resp = reqwest::Client::new()
                    .put(&url)
                    .header("Content-Type", content_type)
                    .body(bytes.to_vec())
                    .send()
                    .await
                    .map_err(|e| ApiError::Internal(e.into()))?;
                if !resp.status().is_success() {
                    let code = resp.status();
                    return Err(ApiError::Internal(anyhow::anyhow!(
                        "S3 upload failed: HTTP {code}"
                    )));
                }
                Ok(())
            }
        }
    }

    /// Best-effort delete (used when a moderator rejects pending media).
    pub async fn delete(&self, key: &str) -> ApiResult<()> {
        match self {
            MediaStore::Local { upload_dir, .. } => {
                let path = PathBuf::from(upload_dir).join(key);
                let _ = fs::remove_file(path).await;
                Ok(())
            }
            MediaStore::S3 { cfg, .. } => {
                let (host, uri, https) = s3_target(cfg, key)?;
                let url = presign_delete_url(
                    &host,
                    &uri,
                    &cfg.region,
                    &cfg.access_key,
                    &cfg.secret_key,
                    PRESIGN_TTL_SECS,
                    https,
                    None,
                )
                .map_err(|e| ApiError::Internal(anyhow::anyhow!("presign delete: {e}")))?;
                let _ = reqwest::Client::new().delete(&url).send().await;
                Ok(())
            }
        }
    }

    /// Clear the `state=unconfirmed` tag so the lifecycle rule no longer expires
    /// the object. Best-effort with one retry; local storage is a no-op.
    pub async fn mark_confirmed(&self, key: &str) -> ApiResult<()> {
        let MediaStore::S3 { cfg } = self else {
            return Ok(());
        };
        let (host, uri, https) = s3_target(cfg, key)?;
        let url = presign_delete_url(
            &host,
            &uri,
            &cfg.region,
            &cfg.access_key,
            &cfg.secret_key,
            PRESIGN_TTL_SECS,
            https,
            Some("tagging"),
        )
        .map_err(|e| ApiError::Internal(anyhow::anyhow!("presign untag: {e}")))?;

        let client = reqwest::Client::new();
        for attempt in 0..2 {
            match client.delete(&url).send().await {
                Ok(resp) if resp.status().is_success() => return Ok(()),
                Ok(resp) => {
                    tracing::warn!(status = %resp.status(), key, "untag attempt failed");
                }
                Err(e) => tracing::warn!(error = %e, key, "untag request error"),
            }
            if attempt == 0 {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            }
        }
        // Non-fatal: the media row is already stored. Worst case the lifecycle
        // rule could expire a confirmed object, so we surface it as an error the
        // caller logs but does not fail the request on.
        Err(ApiError::Internal(anyhow::anyhow!(
            "failed to clear unconfirmed tag for {key}"
        )))
    }
}

fn require(value: &Option<String>, name: &str) -> ApiResult<String> {
    value
        .clone()
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("{name} is required for MEDIA_BACKEND=s3")))
}

fn sanitize_ext(ext: &str) -> String {
    let clean: String = ext
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(8)
        .collect::<String>()
        .to_ascii_lowercase();
    if clean.is_empty() {
        "bin".to_string()
    } else {
        clean
    }
}

/// (host header, canonical uri, use_https) for the given key.
fn s3_target(cfg: &S3Config, key: &str) -> ApiResult<(String, String, bool)> {
    if let Some(ep) = cfg.endpoint.as_ref().filter(|e| !e.trim().is_empty()) {
        let u = url::Url::parse(ep.trim())
            .map_err(|e| ApiError::Internal(anyhow::anyhow!("invalid S3_ENDPOINT: {e}")))?;
        let https = u.scheme() == "https";
        let host = u
            .host_str()
            .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("S3_ENDPOINT has no host")))?
            .to_string();
        let host_header = match u.port() {
            Some(p) => format!("{host}:{p}"),
            None => host,
        };
        let uri = path_style_object_path(&cfg.bucket, key);
        Ok((host_header, uri, https))
    } else {
        let host_header = format!("{}.s3.{}.amazonaws.com", cfg.bucket.trim(), cfg.region.trim());
        let uri = encode_s3_object_path(key);
        Ok((host_header, uri, true))
    }
}
