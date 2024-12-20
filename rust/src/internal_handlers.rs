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
    // MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
    let rides: Vec<Ride> =
        sqlx::query_as("SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 10")
            .fetch_all(&pool)
            .await?;

    if rides.is_empty() {
        return Ok(StatusCode::NO_CONTENT);
    }

    for ride in rides {
        for _ in 0..10 {
            let Some(matched): Option<Chair> = sqlx::query_as(
                "SELECT * FROM chairs WHERE is_active = TRUE ORDER BY RAND() LIMIT 1",
            )
            .fetch_optional(&pool)
            .await?
            else {
                return Ok(StatusCode::NO_CONTENT);
            };

            let empty: bool = sqlx::query_scalar(
                "SELECT NOT EXISTS (
                SELECT 1 FROM rides r
                JOIN ride_statuses rs ON r.id = rs.ride_id
                WHERE r.chair_id = ?
                GROUP BY r.id
                HAVING COUNT(rs.chair_sent_at) != 6
            )",
            )
            .bind(&matched.id)
            .fetch_one(&pool)
            .await?;

            if empty {
                sqlx::query("UPDATE rides SET chair_id = ? WHERE id = ?")
                    .bind(matched.id)
                    .bind(ride.id)
                    .execute(&pool)
                    .await?;
                break;
            }
        }
    }

    Ok(StatusCode::NO_CONTENT)
}

pub async fn internal_get_matching_in_thread(pool: sqlx::MySqlPool) -> Result<(), Error> {
    // MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
    let rides: Vec<Ride> =
        sqlx::query_as("SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 10")
            .fetch_all(&pool)
            .await?;

    if rides.is_empty() {
        return Ok(());
    }

    for ride in rides {
        for _ in 0..10 {
            let Some(matched): Option<Chair> = sqlx::query_as(
                "SELECT * FROM chairs WHERE is_active = TRUE ORDER BY RAND() LIMIT 1",
            )
                .fetch_optional(&pool)
                .await?
            else {
                return Ok(());
            };

            let empty: bool = sqlx::query_scalar(
                "SELECT NOT EXISTS (
                SELECT 1 FROM rides r
                JOIN ride_statuses rs ON r.id = rs.ride_id
                WHERE r.chair_id = ?
                GROUP BY r.id
                HAVING COUNT(rs.chair_sent_at) != 6
            )",
            )
                .bind(&matched.id)
                .fetch_one(&pool)
                .await?;

            if empty {
                sqlx::query("UPDATE rides SET chair_id = ? WHERE id = ?")
                    .bind(matched.id)
                    .bind(ride.id)
                    .execute(&pool)
                    .await?;
                break;
            }
        }
    }

    Ok(())
}
