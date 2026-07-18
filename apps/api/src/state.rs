use std::sync::Arc;

use sqlx::PgPool;

use crate::config::Config;
use crate::push::PushService;
use crate::rate_limit::RateLimiter;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub config: Config,
    pub push: PushService,
    pub rate_limit: Arc<RateLimiter>,
}

impl AppState {
    pub async fn connect(config: Config) -> anyhow::Result<Self> {
        let db = PgPool::connect(&config.database_url).await?;
        let push = PushService::from_env();
        Ok(Self {
            db,
            config,
            push,
            rate_limit: Arc::new(RateLimiter::new()),
        })
    }
}
