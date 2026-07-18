mod auth;
mod config;
mod error;
mod llm;
mod media_sign;
mod media_store;
mod models;
mod push;
mod rate_limit;
mod routes;
mod s3_presign;
mod state;

use std::net::SocketAddr;

use axum::Router;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;
use crate::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    // Prefer monorepo/.env values over empty exports from the shell.
    let _ = dotenvy::from_filename_override(".env");
    let _ = dotenvy::from_filename_override("../../.env");
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "swamy_sharanam_api=debug,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = Config::from_env()?;
    if config.dev_auth {
        tracing::warn!("DEV_AUTH=1 — OTP bypass enabled (dev only)");
    }
    std::fs::create_dir_all(&config.upload_dir)?;
    let state = AppState::connect(config.clone()).await?;

    sqlx::migrate!("./migrations").run(&state.db).await?;
    tracing::info!("migrations applied");

    seed_demo_if_empty(&state).await?;

    let app = Router::new()
        .merge(routes::router())
        .layer(axum::extract::DefaultBodyLimit::max(10 * 1024 * 1024))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr: SocketAddr = config.bind_addr.parse()?;
    tracing::info!("Swamy Sharanam API listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn seed_demo_if_empty(state: &AppState) -> anyhow::Result<()> {
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM trips")
        .fetch_one(&state.db)
        .await?;
    if count.0 > 0 {
        return Ok(());
    }

    let trip_id = uuid::Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO trips (id, title, year, starts_on, ends_on)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(trip_id)
    .bind("Sabarimala Yatra 2026")
    .bind(2026)
    .bind(chrono::NaiveDate::from_ymd_opt(2026, 8, 15).unwrap())
    .bind(chrono::NaiveDate::from_ymd_opt(2026, 8, 20).unwrap())
    .execute(&state.db)
    .await?;

    let leader_user = uuid::Uuid::new_v4();
    let volunteer_user = uuid::Uuid::new_v4();
    let swamy_user = uuid::Uuid::new_v4();

    for (id, phone, name) in [
        (leader_user, "+919999000001", "Guru Swamy (Leader)"),
        (volunteer_user, "+919999000002", "Volunteer One"),
        (swamy_user, "+919999000003", "Kanni Swamy"),
    ] {
        sqlx::query("INSERT INTO users (id, phone_e164, display_name) VALUES ($1, $2, $3)")
            .bind(id)
            .bind(phone)
            .bind(name)
            .execute(&state.db)
            .await?;
    }

    let leader_member = uuid::Uuid::new_v4();
    let volunteer_member = uuid::Uuid::new_v4();
    let swamy_member = uuid::Uuid::new_v4();

    sqlx::query(
        r#"INSERT INTO trip_members (id, trip_id, user_id, role, is_kanni, is_senior, yatra_years)
           VALUES ($1, $2, $3, 'leader', false, true, 5)"#,
    )
    .bind(leader_member)
    .bind(trip_id)
    .bind(leader_user)
    .execute(&state.db)
    .await?;

    sqlx::query(
        r#"INSERT INTO trip_members (id, trip_id, user_id, role, is_kanni, is_senior, yatra_years)
           VALUES ($1, $2, $3, 'volunteer', false, false, 3)"#,
    )
    .bind(volunteer_member)
    .bind(trip_id)
    .bind(volunteer_user)
    .execute(&state.db)
    .await?;

    sqlx::query(
        r#"INSERT INTO trip_members (id, trip_id, user_id, role, is_kanni, is_senior, yatra_years)
           VALUES ($1, $2, $3, 'swamy', true, false, 1)"#,
    )
    .bind(swamy_member)
    .bind(trip_id)
    .bind(swamy_user)
    .execute(&state.db)
    .await?;

    let stops = [
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 15).unwrap(),
            "Mala, Irumudi & Leave for Thrissur",
            "Ravindra’s House, Rajajinagar",
            "Assemble 08:00; board KOCHUVELI EXP 16315 @ 16:35",
            1,
        ),
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 16).unwrap(),
            "Thrissur & Guruvayur temples",
            "Thrissur / Guruvayur",
            "Vadakkunnathan, Paramekkavu, Peruvanam, Triprayar, Guruvayur Seeveli",
            2,
        ),
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 17).unwrap(),
            "To Pampa & Sannidhanam",
            "Sabarimala",
            "Kodungallur, Chottanikkara, Erumely, Nilakkal → climb; Padi Pooja",
            3,
        ),
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 18).unwrap(),
            "Ashta Dravya Abhishekam & descend",
            "Sabarimala → Chengannur",
            "Maalikapurathamma; stay AMDEN RESIDENCY",
            4,
        ),
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 19).unwrap(),
            "Chengannur circuit & return train",
            "Cherthala",
            "Board KCVL MYS EXP 16316 @ 19:40",
            5,
        ),
        (
            chrono::NaiveDate::from_ymd_opt(2026, 8, 20).unwrap(),
            "Bengaluru & Mala removal",
            "Ravindra’s House",
            "Arrival SBC; mala removal ceremony",
            6,
        ),
    ];

    for (day, title, place, notes, sort) in stops {
        sqlx::query(
            r#"INSERT INTO itinerary_stops (trip_id, day_date, title, place_name, notes, sort_order)
               VALUES ($1, $2, $3, $4, $5, $6)"#,
        )
        .bind(trip_id)
        .bind(day)
        .bind(title)
        .bind(place)
        .bind(notes)
        .bind(sort)
        .execute(&state.db)
        .await?;
    }

    let knowledge = [
        (
            "Lost person — Pamba",
            "Going up: wait near start of steps at Pamba Ganapathy (before Virtual Q). Returning: wait near Indian Oil petrol bunk. Network often BSNL-only.",
        ),
        (
            "Lost person — Sabarimala",
            "Wait in front of Holy 18 Steps if below main temple, or near Melshanthi room if on top.",
        ),
        (
            "Train outbound",
            "Train 16315 KOCHUVELI EXP departs ~16:35 on 15 Aug; arrive Thrissur ~02:50 on 16 Aug.",
        ),
        (
            "Train return",
            "Train 16316 KCVL MYS EXP boards Cherthala ~19:40 on 19 Aug; Bengaluru SBC ~08:25 on 20 Aug.",
        ),
    ];

    for (title, content) in knowledge {
        sqlx::query(
            r#"INSERT INTO knowledge_chunks (trip_id, source_title, source_section, content)
               VALUES ($1, $2, $3, $4)"#,
        )
        .bind(trip_id)
        .bind("Shabarimala2026_Aug15-20.pdf")
        .bind(title)
        .bind(content)
        .execute(&state.db)
        .await?;
    }

    let packing = [
        ("Black dhotis with black shalya (extra for rain)", "3+ sets", 1),
        ("Irumudi bag + inner coconut bag (wash if reused)", "1 set", 2),
        ("Swamy mala from previous trip (Kanni: provided)", "1", 3),
        ("Original photo ID / Aadhaar for Virtual Q", "1", 4),
        ("Waist pouch for valuables", "1", 5),
        ("Reusable water bottle for hill climb", "0.5–1 L", 6),
        ("Thin raincoat or blue plastic cover", "1", 7),
        ("Air pillow", "1", 8),
        ("Pen torch / power-bank / charger", "as needed", 9),
        ("Spare plastic covers (wet clothes / prasadham)", "few", 10),
        ("Money + small change (₹10/20/50)", "misc", 11),
        ("Personal medicines (BP, sugar, fever, cold)", "1 week", 12),
        ("Rice from home (do not mix with dal/wheat)", "<200 gms", 13),
        ("Kumkum / turmeric / vibhuti (group may carry)", "optional", 14),
        ("Monetary offerings from friends/family", "if any", 15),
    ];

    for (title, hint, sort) in packing {
        sqlx::query(
            r#"INSERT INTO packing_items (trip_id, title, quantity_hint, sort_order)
               VALUES ($1, $2, $3, $4)"#,
        )
        .bind(trip_id)
        .bind(title)
        .bind(hint)
        .bind(sort)
        .execute(&state.db)
        .await?;
    }

    tracing::info!(%trip_id, "seeded Sabarimala 2026 demo trip + 3 demo users");
    Ok(())
}
