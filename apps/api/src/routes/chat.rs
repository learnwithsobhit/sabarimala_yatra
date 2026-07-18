use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use crate::auth::AuthUserExt;
use crate::error::ApiResult;
use crate::llm::LlmBackend;
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

async fn question_embedding(api_key: &str, question: &str) -> anyhow::Result<Vec<f32>> {
    let body = serde_json::json!({
        "model": "text-embedding-3-small",
        "dimensions": 1536,
        "input": question,
    });
    let json: serde_json::Value = reqwest::Client::new()
        .post("https://api.openai.com/v1/embeddings")
        .bearer_auth(api_key)
        .json(&body)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let values = json["data"][0]["embedding"]
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("embedding missing from response"))?;
    values
        .iter()
        .map(|value| {
            value
                .as_f64()
                .map(|number| number as f32)
                .ok_or_else(|| anyhow::anyhow!("invalid embedding value"))
        })
        .collect()
}

fn vector_literal(values: &[f32]) -> String {
    let values = values
        .iter()
        .map(|value| value.to_string())
        .collect::<Vec<_>>()
        .join(",");
    format!("[{values}]")
}

async fn ask(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<ChatAsk>,
) -> ApiResult<Json<ChatAnswer>> {
    state.rate_limit.check_member_chat(user.member_id)?;
    let q = body.question.trim();
    if q.is_empty() {
        return Ok(Json(ChatAnswer {
            answer: "Please ask a question about the yatra itinerary or guidelines.".into(),
            citations: vec![],
            grounded: false,
            engine: "none".into(),
        }));
    }

    let mut used_vector = false;
    let mut chunks = Vec::<Chunk>::new();
    if let Some(key) = state.config.openai_api_key.as_deref() {
        match question_embedding(key, q).await {
            Ok(embedding) => {
                chunks = sqlx::query_as(
                    r#"
                    SELECT source_title, source_section, content
                    FROM knowledge_chunks
                    WHERE trip_id = $1 AND embedding IS NOT NULL
                    ORDER BY embedding <=> CAST($2 AS vector)
                    LIMIT 4
                    "#,
                )
                .bind(user.trip_id)
                .bind(vector_literal(&embedding))
                .fetch_all(&state.db)
                .await?;
                used_vector = !chunks.is_empty();
            }
            Err(e) => {
                tracing::warn!(error = %e, "OpenAI embedding failed; using keyword retrieval");
            }
        }
    }

    if chunks.is_empty() {
        chunks = sqlx::query_as(
        r#"
        SELECT source_title, source_section, content
        FROM knowledge_chunks
        WHERE trip_id = $1
        "#,
        )
        .bind(user.trip_id)
        .fetch_all(&state.db)
        .await?;
    }

    let top: Vec<&Chunk> = if used_vector {
        chunks.iter().collect()
    } else {
        retrieve(q, &chunks)
    };
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

    if let Some(llm) = LlmBackend::from_env(state.config.openai_api_key.as_deref()) {
        let context = top
            .iter()
            .enumerate()
            .map(|(i, c)| {
                format!(
                    "[{}] {} — {}\n{}",
                    i + 1,
                    c.source_title,
                    c.source_section.as_deref().unwrap_or(""),
                    c.content
                )
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        let system = "You are the Swamy Sharanam trip guide. Answer ONLY from the provided trip excerpts. If the answer is not in the excerpts, say you don't find it in the trip document. Do not invent darshan timings, tickets, or religious rulings. Cite excerpt numbers when helpful.";
        let user_msg = format!("Trip excerpts:\n{context}\n\nQuestion: {q}");
        match llm.complete(system, &user_msg).await {
            Ok(answer) => {
                return Ok(Json(ChatAnswer {
                    answer,
                    citations,
                    grounded: true,
                    engine: llm.name().into(),
                }));
            }
            Err(e) => {
                tracing::warn!(error = %e, engine = llm.name(), "LLM chat failed; falling back to extractive");
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
