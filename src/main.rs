use clap::{Args, Parser, Subcommand};
use git_log_access::{
    config::Config,
    service::{daemon::GitMonitorDaemon, HookManager},
    AppResult,
};
use log::info;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "git-monitor")]
#[command(about = "Cross-platform git command monitor with hook-based interception")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Enable hook-based monitoring
    Start(StartArgs),
    /// Disable hook-based monitoring
    Stop,
    /// Install shell hooks
    Install(InstallArgs),
    /// Remove installed shell hooks
    Uninstall,
    /// Show hook installation and interception status
    Status,
    /// Install hooks, enable interception, and wait until Ctrl+C
    Run(RunArgs),
    /// Internal command used by shell hooks to log git invocations
    #[command(hide = true)]
    Capture(CaptureArgs),
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

#[derive(Args)]
struct CaptureArgs {
    /// Configuration file path
    #[arg(short, long)]
    config: Option<String>,
    /// Shell name that triggered the command
    #[arg(long)]
    shell: Option<String>,
    /// Working directory of the intercepted git command
    #[arg(long)]
    cwd: Option<PathBuf>,
    /// Git arguments passed by the shell hook
    #[arg(trailing_var_arg = true)]
    args: Vec<String>,
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
        Some(Commands::Capture(_)) => {
            env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("error"))
                .init();
        }
        _ => {
            env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
                .init();
        }
    }

    match cli.command {
        Some(Commands::Start(args)) => {
            info!("Enabling git monitor interception...");
            let config = load_config(args.config)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.start_service().await
        }
        Some(Commands::Stop) => {
            info!("Disabling git monitor interception...");
            GitMonitorDaemon::stop_service().await
        }
        Some(Commands::Install(args)) => {
            info!("Installing git monitor shell hooks...");
            let config = load_config(args.config)?;
            GitMonitorDaemon::install_service(&args.name, config).await
        }
        Some(Commands::Uninstall) => {
            info!("Removing git monitor shell hooks...");
            GitMonitorDaemon::uninstall_service().await
        }
        Some(Commands::Status) => {
            info!("Checking git monitor interception status...");
            GitMonitorDaemon::service_status().await
        }
        Some(Commands::Run(args)) => {
            info!("Running git monitor in foreground hook mode...");
            let config = load_config(args.config)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.run_foreground().await
        }
        Some(Commands::Capture(args)) => capture_command(args).await,
        None => {
            info!("Enabling git monitor interception (default)...");
            let config = load_config(None)?;
            let daemon = GitMonitorDaemon::new(config)?;
            daemon.start_service().await
        }
    }
}

fn load_config(config_path: Option<String>) -> AppResult<Config> {
    if let Some(ref path) = config_path {
        info!("Loading configuration from: {}", path);
    } else {
        info!("Loading configured or default settings");
    }

    Config::load_or_default(config_path.as_deref())
}

async fn capture_command(args: CaptureArgs) -> AppResult<()> {
    if !HookManager::is_enabled()? {
        return Ok(());
    }

    let config = load_config(args.config)?;
    let daemon = GitMonitorDaemon::new(config)?;
    let command_line = build_git_command(&args.args);
    daemon
        .process_git_command_with_context(&command_line, args.cwd, args.shell)
        .await
}

fn build_git_command(args: &[String]) -> String {
    if args.is_empty() {
        return "git".to_string();
    }

    let rendered_args = args.iter().map(|arg| {
        if arg.contains(char::is_whitespace) || arg.contains('"') {
            format!("\"{}\"", arg.replace('"', "\\\""))
        } else {
            arg.clone()
        }
    });

    std::iter::once("git".to_string())
        .chain(rendered_args)
        .collect::<Vec<_>>()
        .join(" ")
}
