use actix_web::{App, HttpServer, web};
use uni_stash_be::core::config::Config;
use uni_stash_be::core::db::Db;
use uni_stash_be::core::logging;
use uni_stash_be::core::state::AppState;

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("fatal: failed to load configuration: {err:#}");
            std::process::exit(1);
        }
    };

    // Initialize logging before any other setup.
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

    HttpServer::new(move || {
        App::new()
            // Outermost middleware: every request — including 404s — gets a
            // log line with method, path, status, latency, and request id.
            .wrap(logging::http_middleware())
            .app_data(state.clone())
    })
    .bind(("127.0.0.1", 8080))
    .unwrap()
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
