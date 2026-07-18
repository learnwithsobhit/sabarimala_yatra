use axum::extract::State;
use axum::routing::{get, post, put};
use axum::{Json, Router};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::models::{AssignmentView, MemberRole};
use crate::state::AppState;

#[derive(Debug, Serialize, FromRow)]
struct VehicleRow {
    id: Uuid,
    trip_id: Uuid,
    label: String,
    vehicle_type: String,
    capacity: Option<i32>,
}

#[derive(Debug, Serialize, FromRow)]
struct RoomRow {
    id: Uuid,
    trip_id: Uuid,
    hotel_name: String,
    room_label: String,
    capacity: Option<i32>,
    night_date: Option<NaiveDate>,
}

#[derive(Debug, Serialize, FromRow)]
struct TrainBerthRow {
    id: Uuid,
    trip_id: Uuid,
    train_number: String,
    train_name: Option<String>,
    coach: String,
    berth: Option<String>,
    direction: String,
}

#[derive(Debug, Deserialize)]
struct CreateVehicle {
    label: String,
    #[serde(default = "default_bus")]
    vehicle_type: String,
    capacity: Option<i32>,
}

fn default_bus() -> String {
    "bus".into()
}

#[derive(Debug, Deserialize)]
struct CreateRoom {
    hotel_name: String,
    room_label: String,
    capacity: Option<i32>,
    night_date: Option<NaiveDate>,
}

#[derive(Debug, Deserialize)]
struct CreateTrainBerth {
    train_number: String,
    train_name: Option<String>,
    coach: String,
    berth: Option<String>,
    #[serde(default = "default_outbound")]
    direction: String,
}

fn default_outbound() -> String {
    "outbound".into()
}

#[derive(Debug, Deserialize)]
struct UpsertAssignment {
    member_id: Uuid,
    vehicle_id: Option<Uuid>,
    seat_label: Option<String>,
    room_id: Option<Uuid>,
    train_berth_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
struct Catalog {
    vehicles: Vec<VehicleRow>,
    rooms: Vec<RoomRow>,
    train_berths: Vec<TrainBerthRow>,
}

async fn my_assignment(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Option<AssignmentView>>> {
    let row: Option<AssignmentView> = sqlx::query_as(ASSIGNMENT_SELECT)
        .bind(user.member_id)
        .fetch_optional(&state.db)
        .await?;
    Ok(Json(row))
}

const ASSIGNMENT_SELECT: &str = r#"
SELECT
    tm.id AS member_id,
    u.display_name,
    v.label AS vehicle_label,
    a.seat_label,
    CASE WHEN r.id IS NULL THEN NULL ELSE r.room_label END AS room_label,
    r.hotel_name,
    tb.coach,
    tb.berth,
    tb.train_number
FROM trip_members tm
JOIN users u ON u.id = tm.user_id
LEFT JOIN assignments a ON a.member_id = tm.id
LEFT JOIN vehicles v ON v.id = a.vehicle_id
LEFT JOIN rooms r ON r.id = a.room_id
LEFT JOIN train_berths tb ON tb.id = a.train_berth_id
WHERE tm.id = $1
"#;

const ASSIGNMENT_LIST: &str = r#"
SELECT
    tm.id AS member_id,
    u.display_name,
    v.label AS vehicle_label,
    a.seat_label,
    CASE WHEN r.id IS NULL THEN NULL ELSE r.room_label END AS room_label,
    r.hotel_name,
    tb.coach,
    tb.berth,
    tb.train_number
FROM trip_members tm
JOIN users u ON u.id = tm.user_id
LEFT JOIN assignments a ON a.member_id = tm.id
LEFT JOIN vehicles v ON v.id = a.vehicle_id
LEFT JOIN rooms r ON r.id = a.room_id
LEFT JOIN train_berths tb ON tb.id = a.train_berth_id
WHERE tm.trip_id = $1 AND tm.is_active
ORDER BY u.display_name
"#;

async fn list_all(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<AssignmentView>>> {
    require_helper(&user)?;
    let rows: Vec<AssignmentView> = sqlx::query_as(ASSIGNMENT_LIST)
        .bind(user.trip_id)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows))
}

async fn catalog(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Catalog>> {
    require_helper(&user)?;
    let vehicles: Vec<VehicleRow> = sqlx::query_as(
        "SELECT id, trip_id, label, vehicle_type, capacity FROM vehicles WHERE trip_id = $1 ORDER BY label",
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    let rooms: Vec<RoomRow> = sqlx::query_as(
        "SELECT id, trip_id, hotel_name, room_label, capacity, night_date FROM rooms WHERE trip_id = $1 ORDER BY hotel_name, room_label",
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    let train_berths: Vec<TrainBerthRow> = sqlx::query_as(
        "SELECT id, trip_id, train_number, train_name, coach, berth, direction FROM train_berths WHERE trip_id = $1 ORDER BY train_number, coach, berth",
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(Catalog {
        vehicles,
        rooms,
        train_berths,
    }))
}

async fn create_vehicle(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateVehicle>,
) -> ApiResult<Json<VehicleRow>> {
    require_helper(&user)?;
    let row: VehicleRow = sqlx::query_as(
        r#"
        INSERT INTO vehicles (trip_id, label, vehicle_type, capacity)
        VALUES ($1, $2, $3, $4)
        RETURNING id, trip_id, label, vehicle_type, capacity
        "#,
    )
    .bind(user.trip_id)
    .bind(body.label.trim())
    .bind(body.vehicle_type.trim())
    .bind(body.capacity)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

async fn create_room(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateRoom>,
) -> ApiResult<Json<RoomRow>> {
    require_helper(&user)?;
    let row: RoomRow = sqlx::query_as(
        r#"
        INSERT INTO rooms (trip_id, hotel_name, room_label, capacity, night_date)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, trip_id, hotel_name, room_label, capacity, night_date
        "#,
    )
    .bind(user.trip_id)
    .bind(body.hotel_name.trim())
    .bind(body.room_label.trim())
    .bind(body.capacity)
    .bind(body.night_date)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

async fn create_train_berth(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateTrainBerth>,
) -> ApiResult<Json<TrainBerthRow>> {
    require_helper(&user)?;
    let row: TrainBerthRow = sqlx::query_as(
        r#"
        INSERT INTO train_berths (trip_id, train_number, train_name, coach, berth, direction)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, trip_id, train_number, train_name, coach, berth, direction
        "#,
    )
    .bind(user.trip_id)
    .bind(body.train_number.trim())
    .bind(body.train_name)
    .bind(body.coach.trim())
    .bind(body.berth)
    .bind(body.direction.trim())
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

async fn upsert_assignment(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<UpsertAssignment>,
) -> ApiResult<Json<AssignmentView>> {
    require_helper(&user)?;

    let belongs: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM trip_members WHERE id = $1 AND trip_id = $2 AND is_active",
    )
    .bind(body.member_id)
    .bind(user.trip_id)
    .fetch_optional(&state.db)
    .await?;
    if belongs.is_none() {
        return Err(ApiError::NotFound("Member not on this trip".into()));
    }

    if let Some(vid) = body.vehicle_id {
        let ok: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM vehicles WHERE id = $1 AND trip_id = $2")
                .bind(vid)
                .bind(user.trip_id)
                .fetch_optional(&state.db)
                .await?;
        if ok.is_none() {
            return Err(ApiError::BadRequest("vehicle_id not on this trip".into()));
        }
    }
    if let Some(rid) = body.room_id {
        let ok: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM rooms WHERE id = $1 AND trip_id = $2")
                .bind(rid)
                .bind(user.trip_id)
                .fetch_optional(&state.db)
                .await?;
        if ok.is_none() {
            return Err(ApiError::BadRequest("room_id not on this trip".into()));
        }
    }
    if let Some(bid) = body.train_berth_id {
        let ok: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM train_berths WHERE id = $1 AND trip_id = $2")
                .bind(bid)
                .bind(user.trip_id)
                .fetch_optional(&state.db)
                .await?;
        if ok.is_none() {
            return Err(ApiError::BadRequest(
                "train_berth_id not on this trip".into(),
            ));
        }
    }

    sqlx::query(
        r#"
        INSERT INTO assignments (trip_id, member_id, vehicle_id, seat_label, room_id, train_berth_id, published_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
        ON CONFLICT (trip_id, member_id) DO UPDATE SET
            vehicle_id = EXCLUDED.vehicle_id,
            seat_label = EXCLUDED.seat_label,
            room_id = EXCLUDED.room_id,
            train_berth_id = EXCLUDED.train_berth_id,
            published_at = NOW(),
            updated_at = NOW()
        "#,
    )
    .bind(user.trip_id)
    .bind(body.member_id)
    .bind(body.vehicle_id)
    .bind(body.seat_label)
    .bind(body.room_id)
    .bind(body.train_berth_id)
    .execute(&state.db)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO audit_events (trip_id, actor_member_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, $2, 'assignment.upsert', 'trip_member', $3, $4)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(body.member_id)
    .bind(serde_json::json!({
        "vehicle_id": body.vehicle_id,
        "room_id": body.room_id,
        "train_berth_id": body.train_berth_id,
    }))
    .execute(&state.db)
    .await?;

    let row: AssignmentView = sqlx::query_as(ASSIGNMENT_SELECT)
        .bind(body.member_id)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(row))
}

async fn seed_defaults(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Catalog>> {
    if user.role != MemberRole::Leader {
        return Err(ApiError::Forbidden("Only leader can seed defaults".into()));
    }

    let count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM vehicles WHERE trip_id = $1")
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?;

    if count.0 == 0 {
        for label in ["Bus 1", "Bus 2", "Bus 3"] {
            sqlx::query(
                "INSERT INTO vehicles (trip_id, label, vehicle_type, capacity) VALUES ($1, $2, 'bus', 30)",
            )
            .bind(user.trip_id)
            .bind(label)
            .execute(&state.db)
            .await?;
        }
    }

    let room_count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM rooms WHERE trip_id = $1")
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?;
    if room_count.0 == 0 {
        let hotels = [
            (
                "Pearl Regency, Thrissur",
                "Shared",
                NaiveDate::from_ymd_opt(2026, 8, 16),
            ),
            (
                "Rajavalsam Hotel, Guruvayur",
                "Shared",
                NaiveDate::from_ymd_opt(2026, 8, 16),
            ),
            (
                "Sannidhanam shrine halt",
                "Group",
                NaiveDate::from_ymd_opt(2026, 8, 17),
            ),
            (
                "AMDEN RESIDENCY, Chengannur",
                "Shared",
                NaiveDate::from_ymd_opt(2026, 8, 18),
            ),
        ];
        for (hotel, room, night) in hotels {
            sqlx::query(
                "INSERT INTO rooms (trip_id, hotel_name, room_label, capacity, night_date) VALUES ($1,$2,$3,4,$4)",
            )
            .bind(user.trip_id)
            .bind(hotel)
            .bind(room)
            .bind(night)
            .execute(&state.db)
            .await?;
        }
    }

    let train_count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM train_berths WHERE trip_id = $1")
            .bind(user.trip_id)
            .fetch_one(&state.db)
            .await?;
    if train_count.0 == 0 {
        for (num, name, coach, dir) in [
            ("16315", "KOCHUVELI EXP", "S1", "outbound"),
            ("16315", "KOCHUVELI EXP", "S2", "outbound"),
            ("16315", "KOCHUVELI EXP", "S3", "outbound"),
            ("16316", "KCVL MYS EXP", "S1", "return"),
            ("16316", "KCVL MYS EXP", "S2", "return"),
            ("16316", "KCVL MYS EXP", "S3", "return"),
        ] {
            sqlx::query(
                r#"INSERT INTO train_berths (trip_id, train_number, train_name, coach, direction)
                   VALUES ($1,$2,$3,$4,$5)"#,
            )
            .bind(user.trip_id)
            .bind(num)
            .bind(name)
            .bind(coach)
            .bind(dir)
            .execute(&state.db)
            .await?;
        }
    }

    let trip_id = user.trip_id;
    let vehicles: Vec<VehicleRow> = sqlx::query_as(
        "SELECT id, trip_id, label, vehicle_type, capacity FROM vehicles WHERE trip_id = $1 ORDER BY label",
    )
    .bind(trip_id)
    .fetch_all(&state.db)
    .await?;
    let rooms: Vec<RoomRow> = sqlx::query_as(
        "SELECT id, trip_id, hotel_name, room_label, capacity, night_date FROM rooms WHERE trip_id = $1 ORDER BY hotel_name, room_label",
    )
    .bind(trip_id)
    .fetch_all(&state.db)
    .await?;
    let train_berths: Vec<TrainBerthRow> = sqlx::query_as(
        "SELECT id, trip_id, train_number, train_name, coach, berth, direction FROM train_berths WHERE trip_id = $1 ORDER BY train_number, coach, berth",
    )
    .bind(trip_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(Catalog {
        vehicles,
        rooms,
        train_berths,
    }))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/assignments/me", get(my_assignment))
        .route("/assignments", get(list_all).put(upsert_assignment))
        .route("/assignments/catalog", get(catalog))
        .route("/assignments/vehicles", post(create_vehicle))
        .route("/assignments/rooms", post(create_room))
        .route("/assignments/train-berths", post(create_train_berth))
        .route("/assignments/seed-defaults", post(seed_defaults))
}
