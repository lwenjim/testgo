using System;
using System.Collections.Generic;
using System.CommandLine;
using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using System.Security.Claims;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;
using Microsoft.IdentityModel.Tokens;
using Microsoft.Win32;
using Newtonsoft.Json;

namespace ManageAnonTokyo {
    public static class AppConfig {
        public const string BinPath = "D:\\bin\\bin";
        public const string DocsPath = "C:\\inetpub\\wwwroot";
        public const string DomainExpose = "http://*:8082/";
        public const string ServiceName = "AnonTokyoManage";
        public const string CborDirectoryName = "mastercbor";
        public const string AtConfigDirectoryName = "config";
        public const int DefaultTimeout = 60000;
        public const int ProcessTimeout = 30;
    }

    public class InstallService {
        private const string SuccessCode = "200";
        private const string ErrorCode = "500";
        private const string SuccessMessage = "Service update successfully.";
        private static Dictionary<string, Int64> tokens = new Dictionary<string, Int64>();
        public readonly static DateTime StartDate = DateTime.Now;

        private static readonly Dictionary<string, string> FileMapService = new Dictionary<string, string>() {
            {"AnontokyoServer.exe", "AnonTokyoServer"},
            {"AnonTokyoConfig.zip",  "AnonTokyoServer"},
            {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
            {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer"},
            {"TestGo.exe", "AnonTokyoTestGo"},
            {"AnontokyoDocs.zip", ""},
            {"AnontokyoBuildCbor.exe", "" },
            {"AnontokyoSiriusBuildCbor.exe", "" },
            {"Mysql.zip", "" },
            {"Redis.zip", "" },
        };

        public static int Run(string[] args) {
            var root = new RootCommand("MyApplication");
            var service = new Command("service", "Configure the application");
            var daemon = new Command("daemon", "install window service");
            var run = new Command("run", "deploy and run window service");
            var netinfo = new Command("info", "print network information");

            run.SetAction(async (@params) => {
                await StartService();
            });

            daemon.SetAction((@params) => {
                string result = InstallDaemon();
                if (!string.IsNullOrEmpty(result)) {
                    Console.WriteLine(result);
                }
            });

            netinfo.SetAction((@params) => {
                PrintNetInfo();
            });

            root.Subcommands.Add(service);
            service.Subcommands.Add(daemon);
            service.Subcommands.Add(netinfo);
            service.Subcommands.Add(run);

            return root.Parse(args).Invoke();
        }

        private static async Task<string> HandleZipInstall(string urlName, string domainDownload, PathInfo info, string version) {
            string url = $"{domainDownload}/{urlName}";
            await HandleExeInstall(url, info, version);
            string fullPath, nssmPath, data;
            switch (urlName) {
                case "AnonTokyoSiriusServerCbor.zip":
                    string cborPath = Path.Combine(AppConfig.BinPath, AppConfig.CborDirectoryName);
                    SafeDeleteDirectory(cborPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    break;
                case "AnonTokyoConfig.zip":
                    SafeDeleteDirectory(Path.Combine(AppConfig.BinPath, AppConfig.AtConfigDirectoryName));
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    break;
                case "AnontokyoDocs.zip":
                    string docsPath = Path.Combine(AppConfig.DocsPath, "docs");
                    SafeDeleteDirectory(docsPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.DocsPath);
                    return CreateSuccessResponse();
                case "Mysql.zip":
                    string mysqlServerName = "AnonTokyoMysql";
                    string mysqlDir = $"{AppConfig.BinPath}\\mysql";
                    if (!Directory.Exists(mysqlDir)) {
                        ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    }
                    var result = ExistsService(mysqlServerName);
                    if (result.serviceExists) {
                        StartServiceIfStopped(mysqlServerName);
                        return CreateSuccessResponse();
                    }
                    string dataDir = $"{mysqlDir}\\data";
                    if (!Directory.Exists(dataDir) && RunCommand($"{mysqlDir}\\bin\\mysqld", "--initialize --console") != 0) {
                        return CreateErrorResponse("failed to initialize");
                    }
                    fullPath = $"{mysqlDir}\\bin\\mysqld.exe";
                    nssmPath = GetNssmPath();
                    data = RegisterWindowService(nssmPath, mysqlServerName, fullPath, $"--defaults-file=\"{mysqlDir}\\bin\\my.ini\"");
                    if (!string.IsNullOrEmpty(data)) {
                        return CreateErrorResponse(data);
                    }
                    StartServiceAndWait(mysqlServerName);
                    return CreateSuccessResponse();
                case "Redis.zip":
                    string redisServerName = "AnonTokyoRedis";
                    string redisDir = $"{AppConfig.BinPath}\\redis";
                    StopServiceIfRunning(redisServerName);
                    fullPath = $"{redisDir}\\redis-server.exe";
                    nssmPath = GetNssmPath();
                    if (!Directory.Exists(redisDir)) {
                        ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    }
                    var result2 = ExistsService(redisServerName);
                    if (result2.serviceExists) {
                        StartServiceIfStopped(redisServerName);
                        return CreateSuccessResponse();
                    }
                    data = RegisterWindowService(nssmPath, redisServerName, fullPath, $"{redisDir}\\redis.windows.conf  --loglevel verbose");
                    if (!string.IsNullOrEmpty(data)) {
                        return CreateErrorResponse(data);
                    }
                    StartServiceAndWait(redisServerName);
                    return CreateSuccessResponse();
            }
            return "";
        }

        public static async Task StartService() {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(AppConfig.DomainExpose);
            listener.Start();
            Console.WriteLine($"Listen: {AppConfig.DomainExpose}");
            try {
                while (true) {
                    HttpListenerContext context = await listener.GetContextAsync();
                    _ = ProcessRequest2(context); // Fire and forget
                }
            } finally {
                listener?.Close();
            }
        }

        public static string InstallDaemon() {
            try {
                string executablePath = Assembly.GetExecutingAssembly().Location;
                StopServiceIfRunning(AppConfig.ServiceName);
                UnregisterServiceIfExists(AppConfig.ServiceName);

                if (!Directory.Exists(AppConfig.BinPath)) {
                    Directory.CreateDirectory(AppConfig.BinPath);
                }

                string destFile = Path.Combine(AppConfig.BinPath, Path.GetFileName(executablePath));
                CopyFileWithBackup(executablePath, destFile);

                string nssmPath = GetNssmPath();
                string result = RegisterWindowService(nssmPath, AppConfig.ServiceName, destFile, "service run");
                if (!string.IsNullOrEmpty(result)) {
                    return CreateErrorResponse(result);
                }

                StartServiceAndWait(AppConfig.ServiceName);
                return "";
            } catch (Exception ex) {
                return CreateErrorResponse($"服务安装失败: {ex.Message}");
            }
        }

        private static void StopServiceIfRunning(string serviceName) {
            var result = ExistsService(serviceName);
            if (result.serviceExists) {
                if (result.specificService.Status == ServiceControllerStatus.Running ||
                    result.specificService.Status == ServiceControllerStatus.Paused) {
                    result.specificService.Stop();
                    result.specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }
            }
        }

        private static (ServiceController specificService, bool serviceExists) ExistsService(string serviceName) {
            ServiceController specificService = new ServiceController(serviceName);
            bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));
            return (specificService, serviceExists);
        }

        private static void UnregisterServiceIfExists(string serviceName) {
            bool serviceExists = ServiceController.GetServices()
                .Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));

            if (serviceExists) {
                string nssmPath = GetNssmPath();
                string data = UnRegisterWindowService(nssmPath, serviceName);
                if (!string.IsNullOrEmpty(data)) {
                    throw new Exception(data);
                }
            }
        }

        private static void CopyFileWithBackup(string source, string destination) {
            SafeDeleteFile(destination);
            File.Copy(source, destination);
        }

        private static void SafeDeleteFile(string filePath) {
            if (File.Exists(filePath)) {
                File.Delete(filePath);
            }
        }

        private static void StartServiceAndWait(string serviceName) {
            ServiceController specificService = new ServiceController(serviceName);
            specificService.Start();
            specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(AppConfig.ProcessTimeout));
        }

        public static void PrintNetInfo() {
            Console.WriteLine("\n=== Network Information ===\n");

            PrintIPInfo();
            PrintDnsServers();
            PrintProxyInfo();

            Console.WriteLine();
        }

        private static void PrintIPInfo() {
            string hostName = Dns.GetHostName();
            IPAddress[] addresses = Dns.GetHostAddresses(hostName);
            var validAddresses = addresses.Where(ip => ip.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip));

            string ipAddress = "";
            string subnetMask = "";
            foreach (var address in validAddresses) {
                if (ipAddress.Length < address.ToString().Length) {
                    ipAddress = address.ToString();
                    subnetMask = GetSubnetMaskForIp(address)?.ToString() ?? "";
                }
            }

            Console.WriteLine($"IP Address:  {ipAddress}");
            Console.WriteLine($"Net Mask:    {subnetMask}");
        }

        private static void PrintDnsServers() {
            Console.WriteLine();
            foreach (var dns in GetAllDnsServers()) {
                Console.WriteLine($"DNS Server:  {dns}");
            }
        }

        private static void PrintProxyInfo() {
            Console.WriteLine();
            var proxyInfo = SystemProxyInfo.GetFromRegistry();
            Console.WriteLine($"Proxy Enabled:  {proxyInfo.Enabled}");
            Console.WriteLine($"Proxy Server:   {proxyInfo.Server}");
        }

        public static async Task ProcessRequest2(HttpListenerContext context) {
            try {
                await ProcessRequest(context);
            } catch (Exception ex) {
                Response(context.Response, CreateErrorResponse($"Request processing error: {ex.Message}"));
            }
        }

        private static async Task ProcessRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;
            switch (request.Url.AbsolutePath) {
                case "/deploy":
                    string exeName = context.Request.QueryString.Get("execName");
                    if (string.IsNullOrEmpty(exeName)) {
                        Response(context.Response, CreateErrorResponse("Invalid executable name"));
                        return;
                    }
                    string version = context.Request.QueryString.Get("version");

                    IPEndPoint remoteIP = context.Request.RemoteEndPoint;
                    bool portOpen = await IsTcpPortOpenAsync(remoteIP.Address.ToString(), 80);
                    if (!portOpen) {
                        Response(context.Response, CreateErrorResponse($"Port 80 not open on {remoteIP.Address}"));
                        return;
                    }

                    string responseString = await Install(exeName, version, "http://" + remoteIP.Address);
                    Response(context.Response, responseString);
                    return;
                case "/login":
                    string[] usernames = request.QueryString.GetValues("username");
                    string[] passwords = request.QueryString.GetValues("password");
                    if (usernames.Length == 0 || passwords.Length == 0) {
                        Response(response, 500, "error params");
                        return;
                    }
                    var token = GenerateToken();
                    tokens.Add(token, DateTimeOffset.Now.ToUnixTimeSeconds());
                    response.Headers.Add("token", token);
                    Response(response, 200, token);
                    return;
                case "/info":
                    string[] t = request.QueryString.GetValues("token");
                    if (t.Length == 0 || t[0].Length == 0) {
                        Response(response, 500, "error params");
                        return;
                    }
                    if (!tokens.ContainsKey(t[0])) {
                        Response(response, 500, "not exists");
                        return;
                    }
                    if (DateTimeOffset.Now.ToUnixTimeSeconds() - tokens[t[0]] > 300) {
                        Response(response, 500, "token expired");
                        return;
                    }
                    Response(response, 200, "ok");
                    return;
            }
            string filename = $"{AppConfig.BinPath}\\{request.Url.AbsolutePath}";
            if (File.Exists(filename)) {
                if (Path.GetExtension(filename) != ".html") {
                    response.ContentType = "application/octet-stream";
                } else {
                    response.ContentType = "text/html";
                }
                response.OutputStream.Write(File.ReadAllBytes(filename), 0, (int)new FileInfo(filename).Length);
                response.OutputStream.Close();
                return;
            }
            response.ContentType = "text/html; charset=utf-8";
            DirectoryInfo info = new DirectoryInfo(AppConfig.BinPath);
            StringBuilder sb = new StringBuilder();
            foreach (var item in info.GetFiles().OrderByDescending(f => f.LastWriteTime).ToArray()) {
                sb.AppendLine($"<div class=\"directory-header\"><a href=\"{item.Name}\" class=\"name\">{item.Name}</a><div class=\"size\">{item.Length.ToString("N0")}b</div><div class=\"modified\">{item.LastWriteTime.ToString()}</div></div>");
            }
            string data = $@"
<style>
.directory {{
    font-family: monospace;
    width: 100%;
    max-width: 800px;
}}

.directory-header {{
    display: grid;
    grid-template-columns: 3fr 1fr 1.5fr;
    background: #f0f0f0;
    padding: 8px;
    font-weight: bold;
    border-bottom: 2px solid #ccc;
}}

.directory-row {{
    display: grid;
    grid-template-columns: 3fr 1fr 1.5fr;
    padding: 6px 8px;
    border-bottom: 1px solid #eee;
}}

.directory-row:hover {{
    background-color: #f5f5f5;
}}

.name {{
    text-align: left;
}}

.size {{
    text-align: right;
}}

.modified {{
    text-align: right;
    color: #666;
}}
</style>

<div class=""directory"">
    <div class=""directory-header"">
        <div class=""name"">文件名</div>
        <div class=""size"">大小</div>
        <div class=""modified"">修改时间</div>
    </div>
 {sb.ToString()}   
</div>";
            byte[] buffer = Encoding.UTF8.GetBytes(data);
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
            return;
        }

        public static void Response(HttpListenerResponse response, string responseString) {
            byte[] buffer = Encoding.UTF8.GetBytes(responseString);
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        private static string CreateErrorResponse(string message) {
            return CreateResponse(ErrorCode, message);
        }

        private static string CreateSuccessResponse() {
            return CreateResponse(SuccessCode, SuccessMessage);
        }

        public static string CreateResponse(string code = SuccessCode, string message = SuccessMessage) {
            Dictionary<string, string> responseDict = new Dictionary<string, string>() {
                {"code", code},
                {"message", message},
                {"interval", (DateTime.Now.Subtract(StartDate).TotalSeconds).ToString()},
            };
            return $"{JsonConvert.SerializeObject(responseDict)}\n";
        }

        public async static Task<string> Install(string urlName, string version, string domainDownload) {
            try {
                if (Path.GetExtension(urlName) == ".exe" && !FileMapService.ContainsKey(urlName)) {
                    return CreateErrorResponse($"Invalid executable: {urlName}");
                }
                return await RestartService(urlName, async () => {
                    PathInfo info = GetPathInfo(urlName);
                    string url = $"{domainDownload}/{info.filename}.exe";
                    switch (Path.GetExtension(urlName)) {
                        case ".exe":
                            return await HandleExeInstall(url, info, version);
                        case ".zip":
                            return await HandleZipInstall(urlName, domainDownload, info, version);
                        default:
                            return CreateErrorResponse("Unsupported file type");
                    }
                });
            } catch (Exception ex) {
                return CreateErrorResponse($"操作失败: {ex.Message}");
            }
        }

        private static async Task<string> HandleExeInstall(string url, PathInfo info, string version) {
            // 检查版本
            if (!FileMapService.ContainsKey(Path.GetFileName(url))) {
                return CreateErrorResponse("Invalid executable");
            }
            string binDirPath = Path.GetDirectoryName(info.binPath);
            string filename = Path.GetFileName(info.binPath);
            string tempDir = $"{binDirPath}\\temp";

            if (!Directory.Exists(tempDir)) {
                Directory.CreateDirectory(tempDir);
            }

            DirectoryInfo Dir = new DirectoryInfo(binDirPath);
            FileInfo[] list = Dir.GetFiles($"{filename}*{Path.GetExtension(info.binPath)}", SearchOption.TopDirectoryOnly);
            if (version.Trim().Length == 0) {
                return CreateErrorResponse("empty version");
            }
            // 如果版本号为 -1，自动选择当前目录下版本号最大的文件
            if (version == "-1") {
                Int64 max = 0;
                foreach (var file in list) {
                    string[] cList = file.Name.Split(new char[] { '-', '.' });
                    int.Parse(cList[2]);
                    if (Convert.ToInt64(cList[2]) > max) {
                        max = Convert.ToInt64(cList[2]);
                    }
                }
                if (max > 0) {
                    version = $"{max}";
                }
            }

            // 如果版本号不为 -1，检查当前目录下是否存在对应版本的文件，如果存在则直接复制到目标位置
            string versionFilename = $"{binDirPath}\\history\\{filename}-{version}{Path.GetExtension(info.binPath)}";
            if (!Directory.Exists(Path.GetDirectoryName(versionFilename))) {
                Directory.CreateDirectory(Path.GetDirectoryName(versionFilename));
            }
            if (File.Exists(versionFilename)) {
                if (File.Exists(info.binPath)) {
                    File.Delete(info.binPath);
                }
                File.Copy(versionFilename, info.binPath);
                return "";
            }

            if (version == "-1") {
                return CreateErrorResponse("empty version");
            }

            // 下载新版本
            string destTempFile = $"{tempDir}\\{filename}";
            if (await DownloadFileWithHttpWebRequest(url, destTempFile)) {
                if (File.Exists(info.binPath)) {
                    File.Move(info.binPath, versionFilename);
                }
                File.Move(destTempFile, info.binPath);

                DirectoryInfo directoryInfo = new DirectoryInfo(tempDir) {
                    Attributes = FileAttributes.Normal,
                };
                directoryInfo.Delete(true);
            }
            return "";
        }


        private static void SafeDeleteDirectory(string path) {
            if (Directory.Exists(path)) {
                Directory.Delete(path, true);
            }
        }

        public static async Task<string> RestartService(string urlName, Func<Task<string>> handler) {
            if (string.IsNullOrEmpty(FileMapService[urlName])) {
                string result2 = await handler();
                if (!string.IsNullOrEmpty(result2)) {
                    return result2;
                }
                return CreateSuccessResponse();
            }

            string serviceName = FileMapService[urlName];
            StopServiceIfRunning(serviceName);

            string result = await handler();
            if (!string.IsNullOrEmpty(result)) {
                return result;
            }

            if (Path.GetExtension(urlName) == ".exe" && !ServiceExists(serviceName)) {
                string fullPath = Path.Combine(AppConfig.BinPath, Path.GetFileName(urlName));
                string nssmPath = GetNssmPath();
                string data = RegisterWindowService(nssmPath, serviceName, fullPath);
                if (!string.IsNullOrEmpty(data)) {
                    return CreateErrorResponse(data);
                }
            }

            StartServiceIfStopped(serviceName);
            return CreateSuccessResponse();
        }

        private static bool ServiceExists(string serviceName) {
            return ServiceController.GetServices()
                .Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));
        }

        private static void StartServiceIfStopped(string serviceName) {
            ServiceController service = new ServiceController(serviceName);
            if (service.Status == ServiceControllerStatus.Stopped) {
                service.Start();
                service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(AppConfig.ProcessTimeout));
            }
        }

        public static PathInfo GetPathInfo(string urlName) {
            string binPath = Path.Combine(AppConfig.BinPath, urlName);

            string filename = Path.GetFileNameWithoutExtension(binPath);
            string logPath = Path.Combine(AppConfig.BinPath, $"{filename}.log");

            if (!File.Exists(logPath)) {
                File.Create(logPath).Dispose();
            }

            return new PathInfo() { binPath = binPath, filename = filename, logPath = logPath };
        }

        public static string Response(string code = "200", string message = "Service update successfully.") {
            return CreateResponse(code, message);
        }

        public async static Task<bool> DownloadFileWithHttpWebRequest(string url, string filePath) {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "Mozilla/5.0";
            request.Timeout = AppConfig.DefaultTimeout;

            using (HttpWebResponse response = (HttpWebResponse)await request.GetResponseAsync()) {
                if (response.StatusCode != HttpStatusCode.OK) {
                    throw new Exception($"HTTP error: {response.StatusCode}");
                }

                using (Stream responseStream = response.GetResponseStream())
                using (FileStream fileStream = File.Create(filePath)) {
                    byte[] buffer = new byte[4096];
                    int bytesRead;
                    while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                        await fileStream.WriteAsync(buffer, 0, bytesRead);
                    }
                }
            }
            return true;
        }

        public class PathInfo {
            public string binPath, filename, logPath;
        }

        public static string UnRegisterWindowService(string nssmPath, string serviceName) {
            if (!File.Exists(nssmPath)) {
                return CreateErrorResponse($"nssm.exe not found: {nssmPath}");
            }

            string args = $"remove \"{serviceName}\" confirm";
            if ((RunCommand(nssmPath, args)) != 0) {
                return CreateErrorResponse("Failed to uninstall service");
            }
            return "";
        }

        public static string RegisterWindowService(string nssmPath, string serviceName, string executablePath, string arguments = "", string startType = "SERVICE_AUTO_START") {
            if (!File.Exists(nssmPath)) {
                return CreateErrorResponse($"nssm.exe not found: {nssmPath}");
            }

            if (!File.Exists(executablePath)) {
                return CreateErrorResponse($"Executable not found: {executablePath}");
            }

            try {
                string installArgs = BuildInstallArgs(serviceName, executablePath, arguments);
                if (!TryRunNssmCommand(nssmPath, installArgs)) {
                    return CreateErrorResponse("Failed to install service");
                }

                SetServiceProperties(nssmPath, serviceName, executablePath, startType);
                return "";
            } catch (Exception ex) {
                return CreateErrorResponse($"Service registration failed: {ex.Message}");
            }
        }

        private static string BuildInstallArgs(string serviceName, string executablePath, string arguments) {
            string args = $"install \"{serviceName}\" \"{executablePath}\"";
            if (!string.IsNullOrWhiteSpace(arguments)) {
                args += $" {arguments}";
            }
            return args;
        }

        private static void SetServiceProperties(string nssmPath, string serviceName, string executablePath, string startType) {
            RunCommand(nssmPath, $"set \"{serviceName}\" DisplayName \"{serviceName}\"");
            RunCommand(nssmPath, $"set \"{serviceName}\" Description \"{serviceName}\"");

            if (Path.GetExtension(executablePath) == ".exe") {
                SetServiceLogPaths(nssmPath, serviceName, executablePath);
            }

            if (!string.IsNullOrWhiteSpace(startType)) {
                RunCommand(nssmPath, $"set \"{serviceName}\" Start {startType}");
            }

            RunCommand(nssmPath, $"set \"{serviceName}\" AppRestartDelay 5000");
        }

        private static void SetServiceLogPaths(string nssmPath, string serviceName, string executablePath) {
            string logPath = Path.Combine(
                Path.GetDirectoryName(executablePath),
                Path.GetFileNameWithoutExtension(executablePath) + ".log");

            if (!File.Exists(logPath) && Path.GetExtension(executablePath) == ".exe") {
                File.Create(logPath).Dispose();
            }

            RunCommand(nssmPath, $"set \"{serviceName}\" AppStdin \"{logPath}\"");
            RunCommand(nssmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            RunCommand(nssmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
        }

        private static bool TryRunNssmCommand(string nssmPath, string arguments) {
            return (RunCommand(nssmPath, arguments)) == 0;
        }

        public static int RunCommand(string nssmPath, string arguments) {
            var startInfo = new ProcessStartInfo {
                FileName = nssmPath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            bool needsAdmin = !IsAdministrator();
            if (needsAdmin) {
                startInfo.UseShellExecute = true;
                startInfo.Verb = "runas";
                startInfo.RedirectStandardOutput = false;
                startInfo.RedirectStandardError = false;
            }
            try {
                using (var process = Process.Start(startInfo)) {
                    if (process == null) {
                        Console.WriteLine("Process failed to start");
                        return -2;
                    }
                    process.WaitForExit();
                    if (!needsAdmin) {
                        string output = process.StandardOutput.ReadToEnd();
                        string error = process.StandardError.ReadToEnd();
                        if (!string.IsNullOrEmpty(output)) {
                            Console.WriteLine(output);
                        }
                        if (!string.IsNullOrEmpty(error)) {
                            Console.WriteLine(error);
                        }
                    }
                    if (process.ExitCode > 0) {
                        Console.WriteLine($"Command failed with exit code: {process.ExitCode}");
                    }
                    return process.ExitCode;
                }
            } catch (Exception ex) {
                Console.WriteLine($"Command execution failed: {ex.Message}");
            }
            return -1;
        }

        public static bool IsAdministrator() {
            var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }

        public static string RunCommand(string command) {
            try {
                using (Process process = new Process()) {
                    process.StartInfo.FileName = "cmd.exe";
                    process.StartInfo.Arguments = "/c " + command;
                    process.StartInfo.UseShellExecute = false;
                    process.StartInfo.RedirectStandardOutput = true;
                    process.StartInfo.RedirectStandardError = true;
                    process.StartInfo.CreateNoWindow = true;

                    StringBuilder output = new StringBuilder();
                    process.OutputDataReceived += (sender, e) => output.AppendLine(e.Data);
                    process.ErrorDataReceived += (sender, e) => output.AppendLine(e.Data);

                    process.Start();
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();

                    return output.ToString();
                }
            } catch (Exception ex) {
                return $"Command execution failed: {ex.Message}";
            }
        }

        public static string GetNssmPath() {
            return AppConfig.BinPath + "\\nssm.exe";
        }

        public static async Task<bool> IsTcpPortOpenAsync(string host, int port, int timeoutMilliseconds = 3000) {
            using (TcpClient client = new TcpClient()) {
                try {
                    var connectTask = client.ConnectAsync(host, port);
                    var completedTask = await Task.WhenAny(connectTask, Task.Delay(timeoutMilliseconds));
                    if (completedTask == connectTask) {
                        await connectTask;
                        return true;
                    }
                    return false;
                } catch {
                    return false;
                }
            }
        }

        public static IPAddress GetSubnetMaskForIp(IPAddress ip) {
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces()) {
                if (ni.OperationalStatus == OperationalStatus.Up) {
                    foreach (UnicastIPAddressInformation ipInfo in ni.GetIPProperties().UnicastAddresses) {
                        if (ipInfo.Address.Equals(ip)) {
                            return ipInfo.IPv4Mask;
                        }
                    }
                }
            }
            return null;
        }

        public static List<IPAddress> GetAllDnsServers() {
            var dnsList = new List<IPAddress>();
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces()) {
                if (ni.OperationalStatus == OperationalStatus.Up && ni.NetworkInterfaceType != NetworkInterfaceType.Loopback) {
                    IPInterfaceProperties ipProps = ni.GetIPProperties();
                    foreach (var dns in ipProps.DnsAddresses) {
                        if (dns.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork) {
                            dnsList.Add(dns);
                        }
                    }
                }
            }
            return dnsList.Distinct().ToList();
        }

        public class Result {
            public string Code { get; set; }
            public string Data { get; set; }
            public string Message { get; set; }
        }

        private static void Response(HttpListenerResponse response, Int32 code, string responseString) {
            var data = new Result {
                Code = $"{code}",
                Data = responseString,
                Message = "success"
            };

            byte[] buffer = Encoding.UTF8.GetBytes($"{JsonConvert.SerializeObject(data)}\n");
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        public static string GenerateToken() {
            var secretKey = "your-256-bit-secret-key-here-which-is-long-enough";
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));
            var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var claims = new[]{
            new Claim(JwtRegisteredClaimNames.Sub, "user123"),
            new Claim(JwtRegisteredClaimNames.Email, "user@example.com"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new Claim("role", "admin")
            };

            var token = new JwtSecurityToken(
                issuer: "your-app-name",
                audience: "your-api",
                claims: claims,
                expires: DateTime.UtcNow.AddHours(1),
                signingCredentials: credentials
            );

            var tokenString = new JwtSecurityTokenHandler().WriteToken(token);
            return tokenString;
        }

    }

    public class SystemProxyInfo {
        public bool Enabled { get; set; }
        public string Server { get; set; }
        public string Override { get; set; }
        public bool AutoDetect { get; set; }
        public string AutoConfigUrl { get; set; }
        public static SystemProxyInfo GetFromRegistry() {
            var info = new SystemProxyInfo();
            const string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
            using (RegistryKey registryKey = Registry.CurrentUser.OpenSubKey(keyPath)) {
                if (registryKey != null) {
                    info.Enabled = Convert.ToInt32(registryKey.GetValue("ProxyEnable", 0)) == 1;
                    info.Server = registryKey.GetValue("ProxyServer", "").ToString();
                    info.Override = registryKey.GetValue("ProxyOverride", "").ToString();
                    info.AutoDetect = Convert.ToInt32(registryKey.GetValue("AutoDetect", 0)) == 1;
                    info.AutoConfigUrl = registryKey.GetValue("AutoConfigURL", "").ToString();
                }
            }
            return info;
        }
    }
}
