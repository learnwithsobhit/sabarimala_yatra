CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE knowledge_chunks
    ADD COLUMN IF NOT EXISTS embedding vector(1536);

CREATE INDEX IF NOT EXISTS idx_knowledge_embedding_hnsw
    ON knowledge_chunks
    USING hnsw (embedding vector_cosine_ops)
    WHERE embedding IS NOT NULL;
