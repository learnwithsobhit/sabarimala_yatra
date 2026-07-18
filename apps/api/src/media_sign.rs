//! Short-lived HMAC signed URLs for media file access (NFR-S4).

use chrono::Utc;
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub fn sign_path(secret: &str, storage_key: &str, exp: i64) -> String {
    let mut mac =
        HmacSha256::new_from_slice(secret.as_bytes()).expect("HMAC key length");
    mac.update(storage_key.as_bytes());
    mac.update(b"|");
    mac.update(exp.to_string().as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

pub fn signed_url_path(secret: &str, storage_key: &str) -> String {
    let exp = Utc::now().timestamp() + 3600; // 1 hour
    let sig = sign_path(secret, storage_key, exp);
    format!("/media/files/{storage_key}?exp={exp}&sig={sig}")
}

pub fn verify(secret: &str, storage_key: &str, exp: i64, sig: &str) -> bool {
    if exp < Utc::now().timestamp() {
        return false;
    }
    let expected = sign_path(secret, storage_key, exp);
    // Constant-time-ish compare
    expected.len() == sig.len()
        && expected
            .as_bytes()
            .iter()
            .zip(sig.as_bytes())
            .fold(0u8, |acc, (a, b)| acc | (a ^ b))
            == 0
}
