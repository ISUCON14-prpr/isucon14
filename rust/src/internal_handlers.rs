use axum::extract::State;
use axum::http::StatusCode;

use crate::models::{Chair, Ride};
use crate::{AppState, Error};

pub fn internal_routes() -> axum::Router<AppState> {
    axum::Router::new().route(
        "/api/internal/matching",
        axum::routing::get(internal_get_matching),
    )
}

// このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
async fn internal_get_matching(
    State(AppState { pool, .. }): State<AppState>,
) -> Result<StatusCode, Error> {
    // トランザクション開始
    let mut tx = pool.begin().await?;

    // 待機中のライドを取得（FOR UPDATE でロック）
    let Some(ride): Option<Ride> = sqlx::query_as(
        "SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1 FOR UPDATE"
    )
        .fetch_optional(&tx)
        .await?
    else {
        return Ok(StatusCode::NO_CONTENT);
    };

    // 利用可能な椅子を一度のクエリで取得
    let available_chair: Option<Chair> = sqlx::query_as(
        "SELECT c.* FROM chairs c
         WHERE c.is_active = TRUE
         AND NOT EXISTS (
             SELECT 1 FROM rides r
             JOIN ride_statuses rs ON r.id = rs.ride_id
             WHERE r.chair_id = c.id
             GROUP BY r.id
             HAVING COUNT(rs.chair_sent_at) != 6
         )
         LIMIT 1"
    )
        .fetch_optional(&tx)
        .await?;

    if let Some(chair) = available_chair {
        sqlx::query("UPDATE rides SET chair_id = ? WHERE id = ?")
            .bind(chair.id)
            .bind(ride.id)
            .execute(&tx)
            .await?;
        
        tx.commit().await?;
        Ok(StatusCode::NO_CONTENT)
    } else {
        tx.rollback().await?;
        Ok(StatusCode::NO_CONTENT)
    }
}