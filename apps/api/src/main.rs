pub mod core;

use core::config::Config;
use core::db::Db;

#[actix_web::main]
async fn main() {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("fatal: failed to load configuration: {err:#}");
            std::process::exit(1);
        }
    };

    let database = match Db::connect(&config.database_url).await {
        Ok(db) => db,
        Err(err) => {
            eprintln!("fatal: failed to connect to database: {err:#}");
            std::process::exit(1);
        }
    };

    if Db::should_run_migrations(&config.env)
        && let Err(err) = database.run_migrations().await
    {
        eprintln!("fatal: failed to run migrations: {err:#}");
        std::process::exit(1);
    }

    println!(
        "Hello, world! (env={}, port={}, domains={})",
        config.env,
        config.port,
        config.allowed_email_domains.join(", ")
    );
}
