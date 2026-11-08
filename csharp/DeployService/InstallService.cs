using System;
using System.CommandLine;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Serilog;
using Serilog.Events;

namespace ManageAnonTokyo {
    public static class InstallService {
        private const string DefaultLogLevel = "Information";

        public static void InitializeLogger() {
            Directory.CreateDirectory(AppConfig.LogDirectory);

            LogEventLevel level = LogEventLevel.Information;
            string? configured = Environment.GetEnvironmentVariable("DEPLOY_LOG_LEVEL");
            bool hasInvalidLevel = false;
            if (!string.IsNullOrWhiteSpace(configured)) {
                if (Enum.TryParse(configured, true, out LogEventLevel parsed)) {
                    level = parsed;
                } else {
                    hasInvalidLevel = true;
                }
            }

            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Is(level)
                .WriteTo.Debug(
                    outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
                .WriteTo.File(
                    Path.Combine(AppConfig.LogDirectory, AppConfig.LogFileName),
                    rollingInterval: RollingInterval.Day,
                    outputTemplate: "[{Timestamp:yyyy-MM-dd HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}",
                    retainedFileCountLimit: 30)
                .CreateLogger();

            if (hasInvalidLevel) {
                Log.Warning("Unknown log level {Level}, falling back to {Default}", configured, DefaultLogLevel);
            }

            Log.Information("Logger initialized. Log directory: {LogDir}", AppConfig.LogDirectory);
        }

        public static int Run(string[] args) {
            InitializeLogger();
            try {
                var root = new RootCommand("MyApplication");
                var service = new Command("service", "Configure the application");
                var daemon = new Command("daemon", "install window service");
                var run = new Command("run", "deploy and run window service");
                var netinfo = new Command("info", "print network information");

                run.SetAction(async _ => {
                    using var cts = new CancellationTokenSource();
                    void OnCancelKeyPress(object? _, ConsoleCancelEventArgs e) {
                        e.Cancel = true;
                        try { cts.Cancel(); } catch (ObjectDisposedException) { }
                    }
                    void OnProcessExit(object? _, EventArgs _2) {
                        try { cts.Cancel(); } catch (ObjectDisposedException) { }
                    }
                    Console.CancelKeyPress += OnCancelKeyPress;
                    AppDomain.CurrentDomain.ProcessExit += OnProcessExit;
                    try {
                        await ApiServer.StartService(cts.Token);
                    } finally {
                        Console.CancelKeyPress -= OnCancelKeyPress;
                        AppDomain.CurrentDomain.ProcessExit -= OnProcessExit;
                    }
                });

                daemon.SetAction(_ => {
                    try {
                        ServiceManager.InstallDaemon();
                    } catch (Exception ex) {
                        Log.Error(ex, "Install daemon failed");
                        Environment.ExitCode = 1;
                    }
                });

                netinfo.SetAction(_ => NetworkInfo.PrintNetworkInfo());

                root.Subcommands.Add(service);
                service.Subcommands.Add(daemon);
                service.Subcommands.Add(netinfo);
                service.Subcommands.Add(run);

                return root.Parse(args).Invoke();
            } finally {
                Log.CloseAndFlush();
            }
        }
    }
}