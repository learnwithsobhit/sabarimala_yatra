use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "member_role", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum MemberRole {
    Leader,
    Volunteer,
    Swamy,
}

impl MemberRole {
    pub fn can_start_count(self, helpers_may: bool) -> bool {
        matches!(self, MemberRole::Leader)
            || (helpers_may && matches!(self, MemberRole::Volunteer))
    }

    pub fn can_help_mark(self) -> bool {
        matches!(self, MemberRole::Leader | MemberRole::Volunteer)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "count_session_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CountSessionStatus {
    Open,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "count_mark_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CountMarkStatus {
    Present,
    Missing,
    Excused,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "count_scope_kind", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CountScopeKind {
    All,
    Bus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "announcement_priority", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum AnnouncementPriority {
    Info,
    Urgent,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct Trip {
    pub id: Uuid,
    pub title: String,
    pub year: i32,
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
    pub helpers_may_start_count: bool,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct TripMemberRow {
    pub id: Uuid,
    pub trip_id: Uuid,
    pub user_id: Uuid,
    pub role: MemberRole,
    pub is_kanni: bool,
    pub is_senior: bool,
    pub display_name: String,
    pub phone_e164: String,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct ItineraryStop {
    pub id: Uuid,
    pub trip_id: Uuid,
    pub day_date: NaiveDate,
    pub starts_at: Option<DateTime<Utc>>,
    pub title: String,
    pub place_name: Option<String>,
    pub notes: Option<String>,
    pub map_url: Option<String>,
    pub lost_person_tip: Option<String>,
    pub sort_order: i32,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct CountSession {
    pub id: Uuid,
    pub trip_id: Uuid,
    pub checkpoint_label: String,
    pub scope_kind: CountScopeKind,
    pub scope_vehicle_id: Option<Uuid>,
    pub status: CountSessionStatus,
    pub expected_count: i32,
    pub started_by: Uuid,
    pub started_at: DateTime<Utc>,
    pub closed_by: Option<Uuid>,
    pub closed_at: Option<DateTime<Utc>>,
    pub ready_to_march_note: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct Announcement {
    pub id: Uuid,
    pub trip_id: Uuid,
    pub author_id: Uuid,
    pub priority: AnnouncementPriority,
    pub title: String,
    pub body: String,
    pub count_session_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct AssignmentView {
    pub member_id: Uuid,
    pub display_name: String,
    pub vehicle_label: Option<String>,
    pub seat_label: Option<String>,
    pub room_label: Option<String>,
    pub hotel_name: Option<String>,
    pub coach: Option<String>,
    pub berth: Option<String>,
    pub train_number: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthUser {
    pub user_id: Uuid,
    pub member_id: Uuid,
    pub trip_id: Uuid,
    pub role: MemberRole,
    pub display_name: String,
    pub phone_e164: String,
}
