ALTER TABLE otp_challenges
    ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_otp_phone_created
    ON otp_challenges(phone_e164, created_at DESC);
