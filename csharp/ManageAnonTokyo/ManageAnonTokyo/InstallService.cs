using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    public class InstallService {
        readonly static DateTime StartDate = DateTime.Now;
        const string BinPath = "D:\\bin\\bin";
        const string DomainDownload = "http://localhost";
        const string domainExpose = "http://localhost:8082/";

        public static async Task StartService() {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(domainExpose);
            listener.Start();
            Console.WriteLine($"lissten: {domainExpose} port");
            while (true) {
                HttpListenerContext context = await listener.GetContextAsync();
                await ProcessRequest(context);
            }
        }

        static async Task ProcessRequest(HttpListenerContext context) {
            string exeName = context.Request.QueryString.Get("execName");
            if (exeName == null || exeName.Length == 0) {
                Response(context.Response, "error params");
                return;
            }
            string responseString = await Install(exeName);
            Response(context.Response, responseString);
        }

        static void Response(HttpListenerResponse response, string responseString) {
            byte[] buffer = Encoding.UTF8.GetBytes(responseString);
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        public async static Task<string> Install(string urlName) {
            try {
                Dictionary<string, string> fileMapService = new Dictionary<string, string>() {
                    {"anontokyo_server.exe", "AnonTokyoServer"},
                    {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
                    {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer" },
                };
                if (Path.GetExtension(urlName) == ".exe" && !fileMapService.ContainsKey(urlName)) {
                    return Response("500", "error params");
                }
                return await RestartService(fileMapService, urlName, async () => {
                    PathInfo info = GetBinPathFilenameAndLogname(urlName);
                    string url = $"{DomainDownload}/{info.filename}.exe";
                    switch (Path.GetExtension(urlName)) {
                        case ".exe":
                            if (!fileMapService.ContainsKey(urlName)) {
                                return Response("500", "error params");
                            }
                            await DownloadFileWithHttpWebRequest(url, info.binPath);
                            break;
                        case ".zip":
                            url = $"{DomainDownload}/{urlName}";
                            if (File.Exists(info.binPath)) {
                                File.Delete(info.binPath);
                            }
                            await DownloadFileWithHttpWebRequest(url, info.binPath);
                            if (Directory.Exists(BinPath + "\\mastercbor")) {
                                Directory.Delete(BinPath + "\\mastercbor", true);
                            }
                            ZipFile.ExtractToDirectory(info.binPath, BinPath);
                            break;
                        default:
                            return Response("500", "error params");
                    }
                    return "";
                });
            } catch (Exception ex) {
                return Response("500", $"操作失败: {ex.Message}");
            }
        }

        public static async Task<string> RestartService(Dictionary<string, string> fileMapService, string urlName, Func<Task<string>> handdle) {
            ServiceController specificService = new ServiceController(fileMapService[urlName]);
            bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(fileMapService[urlName], StringComparison.OrdinalIgnoreCase));
            if (serviceExists && (specificService.Status == ServiceControllerStatus.Running || specificService.Status == ServiceControllerStatus.Paused)) {
                specificService.Stop();
                specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
            }
            string result = await handdle();
            if (result.Length > 0) {
                return result;
            }
            if (!serviceExists) {
                string nssmPath = "C:\\ProgramData\\chocolatey\\bin\\nssm.exe";
                string fullName = $"{BinPath}\\{Path.GetFileName(urlName)}";
                string serviceName = fileMapService[urlName];
                string serviceDisplayName = serviceName;
                string description = serviceName;
                if (!Install(nssmPath, serviceName, serviceDisplayName, description, fullName)) {
                    return Response("500", "failed to install");
                }
            }
            if (specificService.Status == ServiceControllerStatus.Stopped) {
                specificService.Start();
                specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
            }
            return Response();
        }

        public static PathInfo GetBinPathFilenameAndLogname(string urlName) {
            string binPath = $"{BinPath}\\{urlName}";
            if (File.Exists(binPath)) {
                File.Delete(binPath);
            }
            string filename = Path.GetFileNameWithoutExtension(binPath);
            string logPath = string.Format($"{BinPath}\\{0}.log", filename);
            if (!File.Exists(logPath)) {
                File.Create(logPath);
            }
            return new PathInfo() { binPath = binPath, filename = filename, logPath = logPath };
        }

        public static string Response(string code = "200", string message = "Service update successfully.") {
            Dictionary<string, string> scores = new Dictionary<string, string>() {
                {"code", code},
                {"message", message },
                {"interval", (DateTime.Now.Subtract(StartDate).TotalSeconds).ToString() },
            };
            return ($"{JsonConvert.SerializeObject(scores)}");
        }

        public async static Task DownloadFileWithHttpWebRequest(string url, string filePath) {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "Mozilla/5.0";
            request.Timeout = 60000;
            HttpWebResponse response = (HttpWebResponse)await request.GetResponseAsync();
            if (response.StatusCode == HttpStatusCode.OK) {
                Stream responseStream = response.GetResponseStream();
                FileStream fileStream = File.Create(filePath);
                byte[] buffer = new byte[4096];
                int bytesRead;
                long totalBytesRead = 0;
                while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                    await fileStream.WriteAsync(buffer, 0, bytesRead);
                    totalBytesRead += bytesRead;
                }
                fileStream.Close();
            } else {
                throw new Exception($"HTTP错误: {response.StatusCode}");
            }
        }

        public class PathInfo {
            public string binPath, filename, logPath;
        }

        public static bool Install(string nssmPath, string serviceName, string serviceDisplayName, string description, string executablePath, string arguments = "", string startType = "SERVICE_AUTO_START") {
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
            string logPath = Path.GetDirectoryName(executablePath) + "\\" + Path.GetFileNameWithoutExtension(executablePath) + ".log";
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
