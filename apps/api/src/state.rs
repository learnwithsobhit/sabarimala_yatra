use sqlx::PgPool;

use crate::config::Config;
use crate::push::PushService;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub config: Config,
    pub push: PushService,
}

impl AppState {
    pub async fn connect(config: Config) -> anyhow::Result<Self> {
        let db = PgPool::connect(&config.database_url).await?;
        let push = PushService::from_env();
        Ok(Self { db, config, push })
    }
}
