//! FCM HTTP v1 push notifications (optional — skip when credentials unset).

use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::Utc;
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::PgPool;
use tokio::sync::Mutex;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct FcmCredentials {
    pub project_id: String,
    pub client_email: String,
    pub private_key_pem: String,
}

impl FcmCredentials {
    /// Load from `FCM_SERVICE_ACCOUNT_PATH` (JSON) or discrete env vars.
    pub fn from_env() -> Option<Self> {
        if let Ok(path) = std::env::var("FCM_SERVICE_ACCOUNT_PATH") {
            if let Ok(raw) = std::fs::read_to_string(&path) {
                return Self::from_service_account_json(&raw).ok();
            }
            tracing::warn!(%path, "FCM_SERVICE_ACCOUNT_PATH unreadable");
        }

        let project_id = std::env::var("FCM_PROJECT_ID").ok()?;
        let client_email = std::env::var("FCM_CLIENT_EMAIL").ok()?;
        let private_key = std::env::var("FCM_PRIVATE_KEY").ok()?;
        if project_id.is_empty() || client_email.is_empty() || private_key.is_empty() {
            return None;
        }
        Some(Self {
            project_id,
            client_email,
            private_key_pem: normalize_pem(&private_key),
        })
    }

    fn from_service_account_json(raw: &str) -> anyhow::Result<Self> {
        #[derive(Deserialize)]
        struct Sa {
            project_id: String,
            client_email: String,
            private_key: String,
        }
        let sa: Sa = serde_json::from_str(raw)?;
        Ok(Self {
            project_id: sa.project_id,
            client_email: sa.client_email,
            private_key_pem: normalize_pem(&sa.private_key),
        })
    }
}

fn normalize_pem(key: &str) -> String {
    key.replace("\\n", "\n")
}

#[derive(Clone)]
pub struct PushService {
    creds: Option<FcmCredentials>,
    http: reqwest::Client,
    token_cache: Arc<Mutex<Option<(String, Instant)>>>,
}

impl PushService {
    pub fn from_env() -> Self {
        let creds = FcmCredentials::from_env();
        if creds.is_some() {
            tracing::info!("FCM push enabled (HTTP v1)");
        } else {
            tracing::info!("FCM push disabled — set FCM_SERVICE_ACCOUNT_PATH or FCM_* env vars");
        }
        Self {
            creds,
            http: reqwest::Client::new(),
            token_cache: Arc::new(Mutex::new(None)),
        }
    }

    async fn access_token(&self, creds: &FcmCredentials) -> anyhow::Result<String> {
        {
            let cache = self.token_cache.lock().await;
            if let Some((tok, exp)) = cache.as_ref() {
                if Instant::now() + Duration::from_secs(60) < *exp {
                    return Ok(tok.clone());
                }
            }
        }

        #[derive(Serialize)]
        struct Claims {
            iss: String,
            scope: String,
            aud: String,
            iat: i64,
            exp: i64,
        }

        let now = Utc::now().timestamp();
        let claims = Claims {
            iss: creds.client_email.clone(),
            scope: "https://www.googleapis.com/auth/firebase.messaging".into(),
            aud: "https://oauth2.googleapis.com/token".into(),
            iat: now,
            exp: now + 3600,
        };
        let key = EncodingKey::from_rsa_pem(creds.private_key_pem.as_bytes())?;
        let jwt = encode(&Header::new(Algorithm::RS256), &claims, &key)?;

        #[derive(Deserialize)]
        struct TokenResp {
            access_token: String,
            expires_in: Option<u64>,
        }

        let resp = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", jwt.as_str()),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<TokenResp>()
            .await?;

        let ttl = Duration::from_secs(resp.expires_in.unwrap_or(3600).saturating_sub(120));
        let mut cache = self.token_cache.lock().await;
        *cache = Some((resp.access_token.clone(), Instant::now() + ttl));
        Ok(resp.access_token)
    }

    async fn send_one(
        &self,
        access_token: &str,
        project_id: &str,
        fcm_token: &str,
        title: &str,
        body: &str,
        data: &serde_json::Value,
        high_priority: bool,
    ) -> Result<(), String> {
        let mut data_map = serde_json::Map::new();
        if let Some(obj) = data.as_object() {
            for (k, v) in obj {
                data_map.insert(
                    k.clone(),
                    json!(match v {
                        serde_json::Value::String(s) => s.clone(),
                        other => other.to_string(),
                    }),
                );
            }
        }
        data_map.insert("title".to_string(), json!(title));
        data_map.insert("body".to_string(), json!(body));

        let priority = if high_priority { "high" } else { "normal" };
        let payload = json!({
            "message": {
                "token": fcm_token,
                "notification": {
                    "title": title,
                    "body": body,
                },
                "data": data_map,
                "android": {
                    "priority": priority,
                    "notification": {
                        "channel_id": if high_priority { "urgent" } else { "default" },
                        "sound": "default"
                    }
                },
                "apns": {
                    "headers": {
                        "apns-priority": if high_priority { "10" } else { "5" }
                    },
                    "payload": {
                        "aps": {
                            "sound": "default",
                            "content-available": 1
                        }
                    }
                }
            }
        });

        let url = format!("https://fcm.googleapis.com/v1/projects/{project_id}/messages:send");
        let resp = self
            .http
            .post(&url)
            .bearer_auth(access_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if resp.status().is_success() {
            return Ok(());
        }

        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        Err(format!("{status}: {text}"))
    }
}

/// Fan-out push to all registered devices for a trip. No-op when FCM unset or no tokens.
pub async fn notify_trip(
    db: &PgPool,
    push: &PushService,
    trip_id: Uuid,
    title: &str,
    body: &str,
    data: serde_json::Value,
    high_priority: bool,
) {
    let tokens: Vec<(String,)> =
        match sqlx::query_as("SELECT fcm_token FROM device_tokens WHERE trip_id = $1")
            .bind(trip_id)
            .fetch_all(db)
            .await
        {
            Ok(t) => t,
            Err(e) => {
                tracing::warn!(error = %e, "failed to load device tokens");
                return;
            }
        };

    if tokens.is_empty() {
        return;
    }

    let Some(creds) = push.creds.as_ref() else {
        tracing::info!(
            tokens = tokens.len(),
            %title,
            "FCM credentials unset — would notify registered devices"
        );
        return;
    };

    let access = match push.access_token(creds).await {
        Ok(t) => t,
        Err(e) => {
            tracing::error!(error = %e, "FCM OAuth failed");
            return;
        }
    };

    let mut ok = 0u32;
    let mut fail = 0u32;
    for (token,) in &tokens {
        match push
            .send_one(
                &access,
                &creds.project_id,
                token,
                title,
                body,
                &data,
                high_priority,
            )
            .await
        {
            Ok(()) => ok += 1,
            Err(err) => {
                fail += 1;
                tracing::warn!(error = %err, "FCM send failed");
                if err.contains("UNREGISTERED") || err.contains("NOT_FOUND") {
                    let _ = sqlx::query("DELETE FROM device_tokens WHERE fcm_token = $1")
                        .bind(token)
                        .execute(db)
                        .await;
                }
            }
        }
    }
    tracing::info!(ok, fail, %title, "FCM fan-out complete");
}
