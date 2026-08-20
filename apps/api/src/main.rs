use actix_web::{App, HttpServer, web};
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::logging;
use uni_stash_be::core::state::AppState;
use uni_stash_be::{configure_health, features};

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("fatal: failed to load configuration: {err:#}");
            std::process::exit(1);
        }
    };

    logging::init(&config.env);

    let db = match Db::connect(&config.database_url).await {
        Ok(db) => db,
        Err(err) => {
            tracing::error!("fatal: failed to connect to database: {err}");
            std::process::exit(1);
        }
    };
    run_migrations(&config.env, &db).await?;
    let state = web::Data::new(
        AppState::new(&config, db)
            .map_err(|e| anyhow::anyhow!("failed to build app state: {e:#}"))?,
    );

    let port = config.port;

    HttpServer::new(move || {
        App::new()
            .wrap(logging::http_middleware())
            .app_data(state.clone())
            .configure(configure_health)
            .configure(features::auth::configure)
    })
    // 0.0.0.0, not 127.0.0.1 — Render's proxy connects from outside the
    // container's loopback interface. Port comes from Config (CM-1.2),
    // which Render overrides via the PORT env var at runtime.
    .bind(("0.0.0.0", port))?
    .run()
    .await?;

    Ok(())
}

async fn run_migrations(env: &str, db: &Db) -> anyhow::Result<()> {
    if Db::should_migrate(env)
        && let Err(err) = db.run_migrations().await
    {
        tracing::error!("fatal: failed to run migrations: {err}");
        std::process::exit(1);
    }
    Ok(())
}
