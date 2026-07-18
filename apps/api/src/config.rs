use anyhow::{bail, Context, Result};

const DEFAULT_JWT_SECRET: &str = "dev-change-me-swamy-sharanam-2026";

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub bind_addr: String,
    pub dev_auth: bool,
    pub dev_otp_code: String,
    pub openai_api_key: Option<String>,
    pub upload_dir: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let jwt_secret =
            std::env::var("JWT_SECRET").unwrap_or_else(|_| DEFAULT_JWT_SECRET.into());
        // Default OFF — must opt into DEV_AUTH=1 for local OTP bypass.
        let dev_auth = std::env::var("DEV_AUTH").unwrap_or_else(|_| "0".into()) == "1";

        if !dev_auth && jwt_secret == DEFAULT_JWT_SECRET {
            bail!(
                "Refusing to start: set a strong JWT_SECRET when DEV_AUTH=0 (production). \
                 Current JWT_SECRET is the insecure default."
            );
        }
        if jwt_secret.len() < 24 {
            bail!("JWT_SECRET must be at least 24 characters");
        }

        Ok(Self {
            database_url: std::env::var("DATABASE_URL").context("DATABASE_URL is required")?,
            jwt_secret,
            bind_addr: std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            dev_auth,
            dev_otp_code: std::env::var("DEV_OTP_CODE").unwrap_or_else(|_| "123456".into()),
            openai_api_key: std::env::var("OPENAI_API_KEY").ok().filter(|s| !s.is_empty()),
            upload_dir: std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".into()),
        })
    }
}
