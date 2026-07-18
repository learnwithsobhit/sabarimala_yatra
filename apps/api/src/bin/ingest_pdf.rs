use anyhow::{bail, Context, Result};
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Deserialize)]
struct EmbeddingResponse {
    data: Vec<EmbeddingItem>,
}

#[derive(Deserialize)]
struct EmbeddingItem {
    embedding: Vec<f32>,
}

fn chunks(text: &str, max_chars: usize) -> Vec<String> {
    let paragraphs = text
        .split("\n\n")
        .map(str::trim)
        .filter(|p| !p.is_empty());
    let mut result = Vec::new();
    let mut current = String::new();
    for paragraph in paragraphs {
        if !current.is_empty() && current.len() + paragraph.len() + 2 > max_chars {
            result.push(current);
            current = String::new();
        }
        if !current.is_empty() {
            current.push_str("\n\n");
        }
        current.push_str(paragraph);
    }
    if !current.is_empty() {
        result.push(current);
    }
    result
}

fn section_title(content: &str, index: usize) -> String {
    const HEADINGS: &[&str] = &[
        "High level Plan",
        "Detailed Plan",
        "15th August",
        "16th August",
        "17th August",
        "18th August",
        "19th August",
        "20th August",
        "Mandala Vratham Start Date",
        "Things to Do Before Leaving the House",
        "Travel Items Checklist",
        "What to do if you are lost",
        "108 Ayyappa Sharanam",
        "How to Observe Mandala Vratham",
    ];
    if let Some(heading) = HEADINGS.iter().find(|heading| content.contains(**heading)) {
        return (*heading).to_string();
    }
    content
        .lines()
        .map(str::trim)
        .find(|line| {
            !line.is_empty()
                && line.len() <= 100
                && !line.chars().all(|c| c.is_ascii_digit())
                && !line.starts_with("--")
                && !line.starts_with("http")
        })
        .map(str::to_string)
        .unwrap_or_else(|| format!("Chunk {index}"))
}

fn vector_literal(values: &[f32]) -> String {
    let values = values
        .iter()
        .map(|v| v.to_string())
        .collect::<Vec<_>>()
        .join(",");
    format!("[{values}]")
}

async fn embeddings(api_key: &str, input: &[String]) -> Result<Vec<Vec<f32>>> {
    let response = reqwest::Client::new()
        .post("https://api.openai.com/v1/embeddings")
        .bearer_auth(api_key)
        .json(&serde_json::json!({
            "model": "text-embedding-3-small",
            "dimensions": 1536,
            "input": input,
        }))
        .send()
        .await?
        .error_for_status()?
        .json::<EmbeddingResponse>()
        .await?;
    Ok(response.data.into_iter().map(|item| item.embedding).collect())
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    let args = std::env::args().collect::<Vec<_>>();
    if args.len() < 2 {
        bail!("usage: cargo run --bin ingest_pdf -- <file.pdf> [trip_uuid]");
    }

    let path = &args[1];
    let source_title = std::path::Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("trip-document.pdf");
    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL is required")?;
    let api_key = std::env::var("OPENAI_API_KEY")
        .ok()
        .filter(|value| !value.trim().is_empty());
    let pool = PgPool::connect(&database_url).await?;
    sqlx::migrate!().run(&pool).await?;

    let trip_id = if let Some(value) = args.get(2) {
        Uuid::parse_str(value).context("trip_uuid is invalid")?
    } else {
        sqlx::query_scalar::<_, Uuid>("SELECT id FROM trips ORDER BY starts_on DESC LIMIT 1")
            .fetch_one(&pool)
            .await
            .context("no trip exists; pass a trip UUID after the PDF path")?
    };

    let text = pdf_extract::extract_text(path)
        .with_context(|| format!("could not extract text from {path}"))?;
    let chunks = chunks(&text, 1_500);
    if chunks.is_empty() {
        bail!("the PDF did not contain extractable text");
    }

    let mut transaction = pool.begin().await?;
    sqlx::query("DELETE FROM knowledge_chunks WHERE trip_id = $1 AND source_title = $2")
        .bind(trip_id)
        .bind(source_title)
        .execute(&mut *transaction)
        .await?;

    for (batch_index, batch) in chunks.chunks(32).enumerate() {
        let vectors = if let Some(key) = api_key.as_deref() {
            let result = embeddings(key, batch).await?;
            if result.len() != batch.len() {
                bail!("embedding response count did not match the input count");
            }
            Some(result)
        } else {
            None
        };
        for (index, content) in batch.iter().enumerate() {
            let section = section_title(content, batch_index * 32 + index + 1);
            if let Some(vectors) = vectors.as_ref() {
                sqlx::query(
                    r#"
                    INSERT INTO knowledge_chunks
                        (trip_id, source_title, source_section, content, embedding)
                    VALUES ($1, $2, $3, $4, CAST($5 AS vector))
                    "#,
                )
                .bind(trip_id)
                .bind(source_title)
                .bind(section)
                .bind(content)
                .bind(vector_literal(&vectors[index]))
                .execute(&mut *transaction)
                .await?;
            } else {
                sqlx::query(
                    r#"
                    INSERT INTO knowledge_chunks
                        (trip_id, source_title, source_section, content)
                    VALUES ($1, $2, $3, $4)
                    "#,
                )
                .bind(trip_id)
                .bind(source_title)
                .bind(section)
                .bind(content)
                .execute(&mut *transaction)
                .await?;
            }
        }
    }
    transaction.commit().await?;
    if api_key.is_none() {
        eprintln!(
            "OPENAI_API_KEY is not set; chunks were ingested without embeddings. \
             Run this command again after setting the key to add vector retrieval."
        );
    }
    println!("Ingested {} chunks from {} for trip {}", chunks.len(), source_title, trip_id);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{chunks, section_title};

    #[test]
    fn chunks_paragraphs_without_dropping_text() {
        let result = chunks("First paragraph.\n\nSecond paragraph.", 20);
        assert_eq!(result, ["First paragraph.", "Second paragraph."]);
    }

    #[test]
    fn uses_known_heading_for_citation() {
        assert_eq!(
            section_title("10\nWhat to do if you are lost?\nWait at the entrance.", 1),
            "What to do if you are lost"
        );
    }
}
