//! Simple in-memory sliding-window rate limits (per-process).
//! For multi-instance Railway, prefer Redis later — this covers NFR-S6 for one replica.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use uuid::Uuid;

use crate::error::{ApiError, ApiResult};

#[derive(Default)]
pub struct RateLimiter {
    inner: Mutex<HashMap<String, Vec<Instant>>>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Allow at most `max` events in `window` for `key`.
    pub fn check(&self, key: &str, max: usize, window: Duration) -> ApiResult<()> {
        let mut map = self.inner.lock().unwrap();
        let now = Instant::now();
        let entry = map.entry(key.to_string()).or_default();
        entry.retain(|t| now.duration_since(*t) < window);
        if entry.len() >= max {
            return Err(ApiError::TooManyRequests(
                "Too many requests — please wait a moment and try again.".into(),
            ));
        }
        entry.push(now);
        Ok(())
    }

    pub fn check_member_chat(&self, member_id: Uuid) -> ApiResult<()> {
        // Soft FAQ cache target: cap LLM/chat asks
        self.check(&format!("chat:{member_id}"), 30, Duration::from_secs(3600))
    }

    pub fn check_member_announce(&self, member_id: Uuid) -> ApiResult<()> {
        self.check(
            &format!("announce:{member_id}"),
            20,
            Duration::from_secs(3600),
        )
    }
}
