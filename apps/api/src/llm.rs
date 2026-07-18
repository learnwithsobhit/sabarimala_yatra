//! LLM backends — OpenAI for trip-time; local Qwen (Ollama-compatible) as post-yatra option.

use serde_json::json;

pub enum LlmBackend {
    OpenAi { api_key: String, model: String },
    Qwen { base_url: String, model: String },
}

impl LlmBackend {
    pub fn from_env(openai_key: Option<&str>) -> Option<Self> {
        let backend = std::env::var("LLM_BACKEND").unwrap_or_else(|_| "openai".into());
        match backend.as_str() {
            "qwen" => Some(Self::Qwen {
                base_url: std::env::var("QWEN_BASE_URL")
                    .unwrap_or_else(|_| "http://127.0.0.1:11434".into()),
                model: std::env::var("QWEN_MODEL").unwrap_or_else(|_| "qwen2.5:7b".into()),
            }),
            _ => openai_key.map(|k| Self::OpenAi {
                api_key: k.to_string(),
                model: std::env::var("OPENAI_CHAT_MODEL")
                    .unwrap_or_else(|_| "gpt-4o-mini".into()),
            }),
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::OpenAi { .. } => "openai",
            Self::Qwen { .. } => "qwen",
        }
    }

    pub async fn complete(&self, system: &str, user: &str) -> anyhow::Result<String> {
        let (endpoint, bearer, model) = match self {
            Self::OpenAi { api_key, model } => (
                "https://api.openai.com/v1/chat/completions".to_string(),
                Some(api_key.clone()),
                model.clone(),
            ),
            Self::Qwen { base_url, model } => (
                format!("{}/v1/chat/completions", base_url.trim_end_matches('/')),
                None,
                model.clone(),
            ),
        };
        let body = json!({
            "model": model,
            "temperature": 0.2,
            "messages": [
                { "role": "system", "content": system },
                { "role": "user", "content": user }
            ]
        });
        let mut req = reqwest::Client::new().post(&endpoint).json(&body);
        if let Some(token) = bearer {
            req = req.bearer_auth(token);
        }
        let json: serde_json::Value = req.send().await?.error_for_status()?.json().await?;
        Ok(json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("I could not form an answer.")
            .to_string())
    }
}
