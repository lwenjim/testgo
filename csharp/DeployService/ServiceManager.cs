using Serilog;
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.ServiceProcess;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    /// <summary>
    /// 外部进程执行。输出与错误流在等待退出前异步读取，避免管道缓冲区写满导致死锁。
    /// </summary>
    public static class ProcessRunner {
        public static (int ExitCode, string Output, string Error) Run(string executable, string arguments) {
            try {
                using var process = Process.Start(CreateStartInfo(executable, arguments));
                if (process == null) {
                    return (-2, "", "启动进程失败");
                }
                var outputTask = process.StandardOutput.ReadToEndAsync();
                var errorTask = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                string output = outputTask.GetAwaiter().GetResult();
                string error = errorTask.GetAwaiter().GetResult();
                Log.Debug("Exit:{ExitCode},Out:{Output},Err:{Error}", process.ExitCode, output, error);
                return (process.ExitCode, output, error);
            } catch (Exception ex) {
                return (-99, "", ex.Message);
            }
        }

        public static async Task<(int ExitCode, string Output, string Error)> RunAsync(string executable, string arguments) {
            try {
                using var process = new Process { StartInfo = CreateStartInfo(executable, arguments) };
                if (!process.Start()) {
                    return (-2, "", "启动进程失败");
                }
                var outputTask = process.StandardOutput.ReadToEndAsync();
                var errorTask = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync();
                string output = await outputTask;
                string error = await errorTask;
                Log.Debug("Exit:{ExitCode},Out:{Output},Err:{Error}", process.ExitCode, output, error);
                return (process.ExitCode, output, error);
            } catch (Exception ex) {
                return (-99, "", ex.Message);
            }
        }

        private static ProcessStartInfo CreateStartInfo(string executable, string arguments) {
            Log.Debug("Running command: {Command} {Args}", executable, arguments);
            return new ProcessStartInfo {
                FileName = executable,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
        }
    }

    /// <summary>
    /// Windows 服务管理（基于 NSSM）。失败时抛出 InvalidOperationException，由调用方统一处理。
    /// </summary>
    public static class ServiceManager {
        public static string GetNssmPath() {
            return Path.Combine(AppConfig.BinPath, "nssm.exe");
        }

        public static bool Exists(string serviceName) {
            using var controller = TryOpen(serviceName);
            return controller != null;
        }

        public static void StopIfRunning(string serviceName) {
            using var controller = TryOpen(serviceName);
            if (controller == null) {
                return;
            }
            if (controller.Status is ServiceControllerStatus.Running or ServiceControllerStatus.Paused) {
                controller.Stop();
                controller.WaitForStatus(
                    ServiceControllerStatus.Stopped,
                    TimeSpan.FromSeconds(AppConfig.ServiceStopTimeoutSeconds));
            }
        }

        public static void StartIfStopped(string serviceName) {
            using var controller = TryOpen(serviceName);
            if (controller == null || controller.Status != ServiceControllerStatus.Stopped) {
                return;
            }
            Log.Information("Starting service {ServiceName}", serviceName);
            controller.Start();
            controller.WaitForStatus(
                ServiceControllerStatus.Running,
                TimeSpan.FromSeconds(AppConfig.ServiceStartTimeoutSeconds));
            Log.Information("Service {ServiceName} is now running", serviceName);
        }

        public static void StartAndWait(string serviceName) {
            using var controller = new ServiceController(serviceName);
            controller.Start();
            controller.WaitForStatus(
                ServiceControllerStatus.Running,
                TimeSpan.FromSeconds(AppConfig.ServiceStartTimeoutSeconds));
        }

        public static void Register(
            string serviceName,
            string executablePath,
            string arguments = "",
            string startType = "SERVICE_AUTO_START") {
            string nssmPath = GetNssmPath();
            if (!File.Exists(nssmPath)) {
                throw new InvalidOperationException($"nssm.exe not found: {nssmPath}");
            }
            if (!File.Exists(executablePath)) {
                throw new InvalidOperationException($"Executable not found: {executablePath}");
            }

            string installArgs = $"install \"{serviceName}\" \"{executablePath}\"";
            if (!string.IsNullOrWhiteSpace(arguments)) {
                installArgs += $" {arguments}";
            }
            if (ProcessRunner.Run(nssmPath, installArgs).ExitCode != 0) {
                throw new InvalidOperationException("Failed to install service");
            }

            ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" DisplayName \"{serviceName}\"");
            ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" Description \"{serviceName}\"");

            if (Path.GetExtension(executablePath).Equals(".exe", StringComparison.OrdinalIgnoreCase)) {
                ConfigureLogPaths(serviceName, executablePath);
            }

            if (!string.IsNullOrWhiteSpace(startType)) {
                ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" Start {startType}");
            }

            ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" AppRestartDelay 5000");
        }

        public static void Unregister(string serviceName) {
            if (!Exists(serviceName)) {
                return;
            }
            string nssmPath = GetNssmPath();
            if (!File.Exists(nssmPath)) {
                throw new InvalidOperationException($"nssm.exe not found: {nssmPath}");
            }
            if (ProcessRunner.Run(nssmPath, $"remove \"{serviceName}\" confirm").ExitCode != 0) {
                throw new InvalidOperationException("Failed to uninstall service");
            }
        }

        /// <summary>
        /// 将当前程序安装为 Windows 服务。若目标路径就是当前运行的程序，则跳过复制。
        /// </summary>
        public static void InstallDaemon() {
            string executablePath = Assembly.GetExecutingAssembly().Location;

            StopIfRunning(AppConfig.ServiceName);
            Unregister(AppConfig.ServiceName);

            Directory.CreateDirectory(AppConfig.BinPath);

            string destFile = Path.Combine(AppConfig.BinPath, Path.GetFileName(executablePath));
            if (!string.Equals(
                    Path.GetFullPath(executablePath),
                    Path.GetFullPath(destFile),
                    StringComparison.OrdinalIgnoreCase)) {
                File.Copy(executablePath, destFile, overwrite: true);
            }

            Register(AppConfig.ServiceName, destFile, "service run");
            StartAndWait(AppConfig.ServiceName);
        }

        private static ServiceController? TryOpen(string serviceName) {
            try {
                var controller = new ServiceController(serviceName);
                _ = controller.Status;
                return controller;
            } catch (InvalidOperationException) {
                return null;
            } catch (ArgumentException) {
                return null;
            }
        }

        private static void ConfigureLogPaths(string serviceName, string executablePath) {
            string logDir = Path.Combine(Path.GetDirectoryName(executablePath)!, "logs");
            Directory.CreateDirectory(logDir);

            string logPath = Path.Combine(logDir, $"{Path.GetFileNameWithoutExtension(executablePath)}.log");
            if (!File.Exists(logPath)) {
                File.Create(logPath).Dispose();
            }

            string nssmPath = GetNssmPath();
            ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            ProcessRunner.Run(nssmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
        }
    }

    public static class FileUtil {
        public static void DeleteIfExists(string filePath) {
            if (File.Exists(filePath)) {
                File.Delete(filePath);
            }
        }

        public static void DeleteDirectoryIfExists(string path) {
            if (Directory.Exists(path)) {
                Directory.Delete(path, true);
            }
        }
    }
}
