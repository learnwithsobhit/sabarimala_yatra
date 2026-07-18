# Yatra PDF ingestion

The API stores 1,536-dimension embeddings in Postgres with `pgvector`. Local
Docker already uses `pgvector/pgvector:pg16`; production Postgres must support
the `vector` extension.

Set `DATABASE_URL` and `OPENAI_API_KEY`, then run:

```bash
cd apps/api
cargo run --bin ingest_pdf -- /absolute/path/to/yatra.pdf [trip_uuid]
```

If `trip_uuid` is omitted, the newest trip is used. The command extracts text,
chunks it, creates `text-embedding-3-small` embeddings, and replaces earlier
chunks from the same filename for that trip.

The chat endpoint uses vector similarity when embedded chunks exist. If the
embedding service is unavailable, it falls back to keyword retrieval and still
refuses answers that are not grounded in stored trip content.

Scanned image-only PDFs need OCR before ingestion.
