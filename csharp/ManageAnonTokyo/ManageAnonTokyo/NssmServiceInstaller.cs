using System;
using System.Diagnostics;
using System.IO;

namespace ManageAnonTokyo {
    internal static class NssmServiceInstaller {
        /// <summary>
        /// 安装 Windows 服务（使用 nssm）
        /// </summary>
        /// <param name="nssmPath">nssm.exe 的完整路径</param>
        /// <param name="serviceName">服务名称</param>
        /// <param name="serviceDisplayName">显示名称（可选）</param>
        /// <param name="description">服务描述（可选）</param>
        /// <param name="executablePath">要作为服务运行的可执行文件路径</param>
        /// <param name="arguments">传递给可执行文件的参数（可选）</param>
        /// <param name="startType">启动类型（Auto, Demand, Delayed-Auto 等）</param>
        /// <returns>安装是否成功</returns>
        public static bool InstallService(string nssmPath, string serviceName, string serviceDisplayName, string description, string executablePath, string arguments = "", string startType = "SERVICE_AUTO_START") {
            if (!File.Exists(nssmPath)) {
                Console.WriteLine($"nssm.exe 未找到: {nssmPath}");
                return false;
            }

            if (!File.Exists(executablePath)) {
                Console.WriteLine($"可执行文件未找到: {executablePath}");
                return false;
            }

            string installArgs = $"install \"{serviceName}\" \"{executablePath}\"";
            if (!string.IsNullOrWhiteSpace(arguments)) {
                installArgs += $" {arguments}";
            }

            if (RunNssmCommand(nssmPath, installArgs) != 0) {
                return false;
            }

            if (!string.IsNullOrWhiteSpace(serviceDisplayName)) {
                RunNssmCommand(nssmPath, $"set \"{serviceName}\" DisplayName \"{serviceDisplayName}\"");
            }

            if (!string.IsNullOrWhiteSpace(description)) {
                RunNssmCommand(nssmPath, $"set \"{serviceName}\" Description \"{description}\"");
            }
            string logPath = Path.GetDirectoryName(executablePath) +"\\"+Path.GetFileNameWithoutExtension(executablePath)+".log";
            if (!File.Exists(logPath)) {
                File.Create(logPath);
            }
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStdin \"{logPath}\"");
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
            if (!string.IsNullOrWhiteSpace(startType)) {
                RunNssmCommand(nssmPath, $"set \"{serviceName}\" Start {startType}");
            }

            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppRestartDelay 5000");

            Console.WriteLine($"服务 '{serviceName}' 安装完成。");
            return true;
        }

        private static int RunNssmCommand(string nssmPath, string arguments) {
            var startInfo = new ProcessStartInfo {
                FileName = nssmPath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };

            bool needAdmin = !IsAdministrator();
            if (needAdmin) {
                startInfo.UseShellExecute = true;
                startInfo.Verb = "runas";
                startInfo.RedirectStandardOutput = false;
                startInfo.RedirectStandardError = false;
            }

            try {
                using (var process = Process.Start(startInfo)) {
                    if (process == null) return -1;
                    process.WaitForExit();
                    if (!needAdmin) {
                        string output = process.StandardOutput.ReadToEnd();
                        string error = process.StandardError.ReadToEnd();
                        if (!string.IsNullOrEmpty(output)) {
                            Console.WriteLine(output);
                        }
                        if (!string.IsNullOrEmpty(error)) {
                            Console.WriteLine("错误: " + error);
                        }
                    }
                    return process.ExitCode;
                }
            } catch (Exception ex) {
                Console.WriteLine($"执行 nssm 命令失败: {ex.Message}");
                return -1;
            }
        }

        private static bool IsAdministrator() {
            var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
    }
}
