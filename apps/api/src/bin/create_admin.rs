use clap::Parser;
use std::env;

/// Create or update an admin account.
///
/// Only requires DATABASE_URL in the environment — does not need JWT keys,
/// SMTP config, or any other application config.
#[derive(Parser)]
#[command(name = "create_admin", about = "Create or update an admin account")]
struct Cli {
    /// Admin email address
    #[arg(long)]
    email: String,

    /// Admin password (min 10 characters)
    #[arg(long)]
    password: String,

    /// Display name (default: "Admin")
    #[arg(long, default_value = "Admin")]
    display_name: String,

    /// Admin level: "super" or "standard" (default: "super")
    #[arg(long, default_value = "super")]
    level: String,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    if cli.level != "super" && cli.level != "standard" {
        eprintln!(
            "error: level must be 'super' or 'standard', got '{}'",
            cli.level
        );
        std::process::exit(1);
    }

    // Load .env for DATABASE_URL if present, but don't require it — the
    // variable can come from the process environment directly.
    dotenvy::dotenv().ok();

    let db_url = match env::var("DATABASE_URL") {
        Ok(v) if !v.trim().is_empty() => v,
        _ => {
            eprintln!("fatal: DATABASE_URL is not set");
            std::process::exit(1);
        }
    };

    let pool = match sqlx::postgres::PgPoolOptions::new().connect(&db_url).await {
        Ok(p) => p,
        Err(e) => {
            eprintln!("fatal: failed to connect to database: {e}");
            std::process::exit(1);
        }
    };

    let password_hash = match uni_stash_be::core::auth::password::hash_password(&cli.password) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("fatal: failed to hash password: {e}");
            std::process::exit(1);
        }
    };

    let result = sqlx::query!(
        r#"INSERT INTO admins (email, password_hash, display_name, level)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (email) DO UPDATE SET
               password_hash = EXCLUDED.password_hash,
               level = EXCLUDED.level,
               is_active = true,
               updated_at = now()
           RETURNING id, email, level"#,
        cli.email,
        password_hash,
        cli.display_name,
        cli.level,
    )
    .fetch_one(&pool)
    .await;

    match result {
        Ok(admin) => {
            println!(
                "admin {} created/updated successfully (id: {}, level: {})",
                admin.email, admin.id, admin.level
            );
        }
        Err(e) => {
            eprintln!("fatal: failed to create admin: {e}");
            std::process::exit(1);
        }
    }
}
