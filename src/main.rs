use clap::{Args, Parser, Subcommand};
use git_log_access::{config::Config, service::daemon::GitMonitorDaemon, AppResult};
use log::info;

#[derive(Parser)]
#[command(name = "git-monitor")]
#[command(about = "Cross-platform git command monitoring service")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the monitoring service
    Start(StartArgs),
    /// Stop the monitoring service
    Stop,
    /// Install as system service
    Install(InstallArgs),
    /// Uninstall system service
    Uninstall,
    /// Show service status
    Status,
    /// Run in foreground (for testing)
    Run(RunArgs),
}

#[derive(Args)]
struct StartArgs {
    /// Configuration file path
    #[arg(short, long)]
    config: Option<String>,
}

#[derive(Args)]
struct InstallArgs {
    /// Configuration file path
    #[arg(short, long)]
    config: Option<String>,
    /// Service name
    #[arg(short, long, default_value = "GitMonitor")]
    name: String,
}

#[derive(Args)]
struct RunArgs {
    /// Configuration file path
    #[arg(short, long)]
    config: Option<String>,
    /// Verbose logging
    #[arg(short, long)]
    verbose: bool,
}

#[tokio::main]
async fn main() -> AppResult<()> {
    let cli = Cli::parse();

    // Initialize logging based on command
    match &cli.command {
        Some(Commands::Run(args)) if args.verbose => {
            env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("debug"))
                .init();
        }
        _ => {
            env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
                .init();
        }
    }

    match cli.command {
        Some(Commands::Start(args)) => {
            info!("Starting git monitor service...");
            let config = load_config(args.config)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.start_service().await
        }
        Some(Commands::Stop) => {
            info!("Stopping git monitor service...");
            GitMonitorDaemon::stop_service().await
        }
        Some(Commands::Install(args)) => {
            info!("Installing git monitor service...");
            let config = load_config(args.config)?;
            GitMonitorDaemon::install_service(&args.name, config).await
        }
        Some(Commands::Uninstall) => {
            info!("Uninstalling git monitor service...");
            GitMonitorDaemon::uninstall_service().await
        }
        Some(Commands::Status) => {
            info!("Checking git monitor service status...");
            GitMonitorDaemon::service_status().await
        }
        Some(Commands::Run(args)) => {
            info!("Running git monitor in foreground (testing mode)...");
            let config = load_config(args.config)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.run_foreground().await
        }
        None => {
            // Default behavior: start service
            info!("Starting git monitor service (default)...");
            let config = load_config(None)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.start_service().await
        }
    }
}

fn load_config(config_path: Option<String>) -> AppResult<Config> {
    match config_path {
        Some(path) => {
            info!("Loading configuration from: {}", path);
            Config::from_file(&path)
        }
        None => {
            info!("Loading default configuration");
            Config::default_config()
        }
    }
}
