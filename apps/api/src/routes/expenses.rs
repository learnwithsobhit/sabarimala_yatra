use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::auth::AuthUserExt;
use crate::auth::middleware::require_helper;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

#[derive(Debug, Serialize, FromRow)]
struct ExpenseRow {
    id: Uuid,
    trip_id: Uuid,
    paid_by_member_id: Uuid,
    amount_paise: i64,
    currency: String,
    category: Option<String>,
    note: Option<String>,
    spent_at: DateTime<Utc>,
    payer_name: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateExpense {
    pub amount_rupees: f64,
    pub note: Option<String>,
    pub category: Option<String>,
    /// If empty, split equally among all active members
    pub member_ids: Option<Vec<Uuid>>,
}

#[derive(Debug, Serialize, FromRow)]
struct BalanceRow {
    member_id: Uuid,
    display_name: String,
    net_paise: i64,
}

async fn list_expenses(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<ExpenseRow>>> {
    let rows: Vec<ExpenseRow> = sqlx::query_as(
        r#"
        SELECT e.id, e.trip_id, e.paid_by_member_id, e.amount_paise, e.currency,
               e.category, e.note, e.spent_at, u.display_name AS payer_name
        FROM expenses e
        JOIN trip_members tm ON tm.id = e.paid_by_member_id
        JOIN users u ON u.id = tm.user_id
        WHERE e.trip_id = $1
        ORDER BY e.spent_at DESC
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn create_expense(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
    Json(body): Json<CreateExpense>,
) -> ApiResult<Json<ExpenseRow>> {
    require_helper(&user)?;
    if body.amount_rupees <= 0.0 {
        return Err(ApiError::BadRequest("amount must be positive".into()));
    }
    let amount_paise = (body.amount_rupees * 100.0).round() as i64;

    let member_ids: Vec<Uuid> = if let Some(ids) = body.member_ids.filter(|v| !v.is_empty()) {
        let mut valid = Vec::with_capacity(ids.len());
        for mid in ids {
            let ok: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM trip_members WHERE id = $1 AND trip_id = $2 AND is_active",
            )
            .bind(mid)
            .bind(user.trip_id)
            .fetch_optional(&state.db)
            .await?;
            if ok.is_none() {
                return Err(ApiError::BadRequest(format!(
                    "member_id {mid} is not on this trip"
                )));
            }
            valid.push(mid);
        }
        valid
    } else {
        sqlx::query_scalar(
            "SELECT id FROM trip_members WHERE trip_id = $1 AND is_active",
        )
        .bind(user.trip_id)
        .fetch_all(&state.db)
        .await?
    };

    if member_ids.is_empty() {
        return Err(ApiError::BadRequest("No members to split with".into()));
    }

    let n = member_ids.len() as i64;
    let base = amount_paise / n;
    let mut remainder = amount_paise % n;

    let mut tx = state.db.begin().await?;
    let expense_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO expenses (id, trip_id, paid_by_member_id, amount_paise, category, note, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $3)
        "#,
    )
    .bind(expense_id)
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(amount_paise)
    .bind(&body.category)
    .bind(&body.note)
    .execute(&mut *tx)
    .await?;

    for mid in &member_ids {
        let mut share = base;
        if remainder > 0 {
            share += 1;
            remainder -= 1;
        }
        sqlx::query(
            "INSERT INTO expense_shares (expense_id, member_id, share_paise) VALUES ($1, $2, $3)",
        )
        .bind(expense_id)
        .bind(mid)
        .bind(share)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query(
        r#"
        INSERT INTO audit_events
            (trip_id, actor_member_id, action, entity_type, entity_id, payload_json)
        VALUES ($1, $2, 'expense.create', 'expense', $3, $4)
        "#,
    )
    .bind(user.trip_id)
    .bind(user.member_id)
    .bind(expense_id)
    .bind(serde_json::json!({
        "amount_paise": amount_paise,
        "member_count": member_ids.len(),
        "category": body.category,
    }))
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    let row: ExpenseRow = sqlx::query_as(
        r#"
        SELECT e.id, e.trip_id, e.paid_by_member_id, e.amount_paise, e.currency,
               e.category, e.note, e.spent_at, u.display_name AS payer_name
        FROM expenses e
        JOIN trip_members tm ON tm.id = e.paid_by_member_id
        JOIN users u ON u.id = tm.user_id
        WHERE e.id = $1
        "#,
    )
    .bind(expense_id)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(row))
}

async fn balances(
    State(state): State<AppState>,
    AuthUserExt(user): AuthUserExt,
) -> ApiResult<Json<Vec<BalanceRow>>> {
    let rows: Vec<BalanceRow> = sqlx::query_as(
        r#"
        WITH paid AS (
            SELECT paid_by_member_id AS member_id, SUM(amount_paise) AS paid
            FROM expenses WHERE trip_id = $1 GROUP BY paid_by_member_id
        ),
        owed AS (
            SELECT es.member_id, SUM(es.share_paise) AS share
            FROM expense_shares es
            JOIN expenses e ON e.id = es.expense_id
            WHERE e.trip_id = $1
            GROUP BY es.member_id
        )
        SELECT tm.id AS member_id, u.display_name,
               (COALESCE(p.paid, 0) - COALESCE(o.share, 0))::bigint AS net_paise
        FROM trip_members tm
        JOIN users u ON u.id = tm.user_id
        LEFT JOIN paid p ON p.member_id = tm.id
        LEFT JOIN owed o ON o.member_id = tm.id
        WHERE tm.trip_id = $1 AND tm.is_active
        ORDER BY u.display_name
        "#,
    )
    .bind(user.trip_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/expenses", get(list_expenses).post(create_expense))
        .route("/expenses/balances", get(balances))
}
