pub mod core;

use core::config::Config;
use core::db::Db;

use actix_web::{HttpServer, web};

use crate::core::state::AppState;

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("fatal: failed to load configuration: {err:#}");
            std::process::exit(1);
        }
    };
    let db = match Db::connect(&config.database_url).await {
        Ok(db) => db,
        Err(err) => {
            eprintln!("fatal: failed to connect to database: {err:#}");
            std::process::exit(1);
        }
    };
    run_migrations(&config.env, &db).await?;
    let state = web::Data::new(
        AppState::new(&config, db)
            .map_err(|e| anyhow::anyhow!("failed to build app state: {e:#}"))?,
    );

    HttpServer::new(move || actix_web::App::new().app_data(state.clone()))
        .bind(("127.0.0.1", 8080))
        .unwrap()
        .run()
        .await?;

    Ok(())
}

async fn run_migrations(env: &str, db: &Db) -> anyhow::Result<()> {
    if Db::should_migrate(&env)
        && let Err(err) = db.run_migrations().await
    {
        eprintln!("fatal: failed to run migrations: {err:#}");
        std::process::exit(1);
    }
    Ok(())
}
