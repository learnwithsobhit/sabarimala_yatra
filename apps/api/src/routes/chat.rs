use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use crate::auth::AuthUserExt;
use crate::error::ApiResult;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct ChatAsk {
    pub question: String,
}

#[derive(Serialize)]
pub struct ChatAnswer {
    pub answer: String,
    pub citations: Vec<Citation>,
    pub grounded: bool,
    pub engine: String,
}

#[derive(Serialize)]
pub struct Citation {
    pub source_title: String,
    pub source_section: Option<String>,
}

#[derive(FromRow, Clone)]
struct Chunk {
    source_title: String,
    source_section: Option<String>,
    content: String,
}

fn score(q: &str, content: &str) -> usize {
    let q = q.to_ascii_lowercase();
    let c = content.to_ascii_lowercase();
    q.split_whitespace()
        .filter(|w| w.len() > 2 && c.contains(w))
        .count()
}

fn retrieve<'a>(q: &str, chunks: &'a [Chunk]) -> Vec<&'a Chunk> {
    let mut ranked: Vec<(usize, &Chunk)> = chunks
        .iter()
        .map(|c| {
            (
                score(q, &c.content) + score(q, c.source_section.as_deref().unwrap_or("")),
                c,
            )
        })
        .filter(|(s, _)| *s > 0)
        .collect();
    ranked.sort_by(|a, b| b.0.cmp(&a.0));
    ranked.into_iter().take(4).map(|(_, c)| c).collect()
}

fn extractive_answer(top: &[&Chunk]) -> String {
    top.iter()
        .map(|c| {
            let sec = c
                .source_section
                .as_deref()
                .map(|s| format!("{s}: "))
                .unwrap_or_default();
            format!("{sec}{}", c.content)
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

async fn openai_answer(api_key: &str, question: &str, top: &[&Chunk]) -> anyhow::Result<String> {
    let context = top
        .iter()
        .enumerate()
        .map(|(i, c)| {
            format!(
                "[{}] {} — {}\n{}",
                i + 1,
                c.source_title,
                c.source_section.as_deref().unwrap_or("section"),
                c.content
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n");

    let body = serde_json::json!({
        "model": "gpt-4o-mini",
        "temperature": 0.2,
        "messages": [
            {
                "role": "system",
                "content": "You are a devout, calm assistant for a Sabarimala group yatra app called Swamy Sharanam. Answer ONLY using the provided trip document excerpts. If the answer is not in the excerpts, say you do not find it in the trip document and suggest asking the trip leader. Do not invent darshan timings, tickets, or religious rulings. Keep answers concise. Cite section titles inline when helpful."
            },
            {
                "role": "user",
                "content": format!("Trip excerpts:\n{context}\n\nQuestion: {question}")
            }
        ]
    });

    let client = reqwest::Client::new();
    let res = client
        .post("https://api.openai.com/v1/chat/completions")
        .bearer_auth(api_key)
        .json(&body)
        .send()
        .await?
        .error_for_status()?;
    let json: serde_json::Value = res.json().await?;
    let text = json["choices"][0]["message"]["content"]
        .as_str()
        .unwrap_or("I could not form an answer.")
        .to_string();
    Ok(text)
}

async fn ask(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<ChatAsk>,
) -> ApiResult<Json<ChatAnswer>> {
    let q = body.question.trim();
    if q.is_empty() {
        return Ok(Json(ChatAnswer {
            answer: "Please ask a question about the yatra itinerary or guidelines.".into(),
            citations: vec![],
            grounded: false,
            engine: "none".into(),
        }));
    }

    let chunks: Vec<Chunk> = sqlx::query_as(
        r#"
        SELECT source_title, source_section, content
        FROM knowledge_chunks
        WHERE trip_id = $1
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;

    let top = retrieve(q, &chunks);
    if top.is_empty() {
        return Ok(Json(ChatAnswer {
            answer: "I don't find that in the trip document. Please ask the trip leader, or try a question about schedule, trains, lost-person points, or Mandala guidelines.".into(),
            citations: vec![],
            grounded: false,
            engine: "none".into(),
        }));
    }

    let citations: Vec<Citation> = top
        .iter()
        .map(|c| Citation {
            source_title: c.source_title.clone(),
            source_section: c.source_section.clone(),
        })
        .collect();

    if let Some(key) = state.config.openai_api_key.as_deref() {
        match openai_answer(key, q, &top).await {
            Ok(answer) => {
                return Ok(Json(ChatAnswer {
                    answer,
                    citations,
                    grounded: true,
                    engine: "openai".into(),
                }));
            }
            Err(e) => {
                tracing::warn!(error = %e, "OpenAI chat failed; falling back to extractive");
            }
        }
    }

    Ok(Json(ChatAnswer {
        answer: extractive_answer(&top),
        citations,
        grounded: true,
        engine: "extractive".into(),
    }))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/chat/ask", post(ask))
}
