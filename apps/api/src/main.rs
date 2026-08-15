pub mod core;

use core::config::Config;

fn main() {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("fatal: failed to load configuration: {err:#}");
            std::process::exit(1);
        }
    };

    println!(
        "Hello, world! (env={}, port={}, domains={})",
        config.env,
        config.port,
        config.allowed_email_domains.join(", ")
    );
}
