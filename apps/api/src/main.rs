use actix_web::{App, HttpServer, web};
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db;
use uni_stash_be::core::jobs;
use uni_stash_be::core::logging;
use uni_stash_be::core::metrics;
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

    // Prometheus recorder — before any request can be observed. Failures
    // are fatal only if metrics are explicitly enabled; otherwise degrade
    // to logging-only so a bad METRICS_* var can't take the API down.
    if config.metrics_enabled
        && let Err(err) = metrics::init()
    {
        tracing::error!("failed to install prometheus recorder: {err:#}");
    }

    let db = match db::Db::connect(&config.database_url).await {
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

    // Pool gauges for /metrics (size/idle/in-use, 15s sample).
    db::Db::spawn_pool_metrics(state.db.clone());

    let port = config.port;

    // Spawn background jobs (cleanup, future email scheduling, etc.).
    // Must happen after DB pool is ready but before the server starts
    // accepting requests, so the first cleanup runs promptly.
    jobs::spawn(
        state.db.clone(),
        state.r2_client.clone(),
        state.smtp.clone(),
    );

    HttpServer::new(move || {
        App::new()
            .wrap(logging::http_middleware())
            .app_data(state.clone())
            .configure(configure_health)
            .configure(features::auth::configure)
            .configure(features::admin_auth::configure)
            .configure(features::admin_management::configure)
            .configure(features::admin_moderation::configure)
            .configure(features::listings::configure)
            .configure(features::blocks::configure)
            .configure(features::chats::configure)
            .configure(features::notifications::configure)
            .configure(features::sales::configure)
            .configure(features::saved_items::configure)
            .configure(features::reports::configure)
            .configure(features::reviews::configure)
            .configure(features::images::configure)
            .configure(features::categories::configure)
            .configure(features::schools::configure)
            .configure(features::users::configure)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await?;

    Ok(())
}

async fn run_migrations(env: &str, db: &db::Db) -> anyhow::Result<()> {
    if db::Db::should_migrate(env)
        && let Err(err) = db.run_migrations().await
    {
        tracing::error!("fatal: failed to run migrations: {err}");
        std::process::exit(1);
    }
    Ok(())
}
