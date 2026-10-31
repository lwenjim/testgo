using Microsoft.IdentityModel.Tokens;
using Microsoft.Win32;
using Newtonsoft.Json;
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
using System.Text.RegularExpressions;
using Serilog;
using System.Threading;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    public static class AppConfig {
        public const string BinPath = "D:\\bin\\bin";
        public const string DomainExpose = "http://*:80/";
        public const string ServiceName = "AnonTokyoManage";
        public const string DefaultIndex = "index.html";
        public const string CborDirectoryName = "mastercbor";
        public const string AtConfigDirectoryName = "atmastercbor";
        public const int DefaultTimeout = 60000;
        public const int ProcessTimeout = 30;
        public const string LogDirectory = "D:\\bin\\logs";
        public const string LogFileName = "deploy-service-.log";
    }

    public class InstallService {
        private const string SuccessCode = "200";
        private const string ErrorCode = "500";
        private const string SuccessMessage = "Service update successfully.";
        private static Dictionary<string, Int64> tokens = new Dictionary<string, Int64>();
        public static DateTime StartDate = DateTime.Now;

        public static void InitializeLogger() {
            if (!Directory.Exists(AppConfig.LogDirectory)) {
                Directory.CreateDirectory(AppConfig.LogDirectory);
            }
            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Debug()
                .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
                .WriteTo.File(
                    Path.Combine(AppConfig.LogDirectory, AppConfig.LogFileName),
                    rollingInterval: RollingInterval.Day,
                    outputTemplate: "[{Timestamp:yyyy-MM-dd HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}",
                    retainedFileCountLimit: 30)
                .CreateLogger();
            Log.Information("Logger initialized. Log directory: {LogDir}", AppConfig.LogDirectory);
        }

        private static readonly Dictionary<string, string> FileMapService = new Dictionary<string, string>() {
            {"AnontokyoServer.exe", "AnonTokyoServer"},
            {"AnonTokyoConfig.zip",  "AnonTokyoServer"},
            {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
            {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer"},
            {"TestGo.exe", "AnonTokyoTestGo"},
            {"AnontokyoDocs.zip", ""},
            {"AnontokyoBuildCbor.exe", "" },
            {"AnontokyoSiriusBuildCbor.exe", "" },
            {"Mysql.zip", "Mysql" },
            {"Redis.zip", "Redis" },
        };

        private static async Task ProcessRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;
            StartDate = DateTime.Now;
            Log.Information("Received request: {Method} {Path} from {RemoteEP}", request.HttpMethod, request.Url!.AbsolutePath, context.Request.RemoteEndPoint);

            if (await TryHandleApiRequest(context)) {
                return;
            }

            await ServeStaticContent(context);
        }

        private static async Task<bool> TryHandleApiRequest(HttpListenerContext context) {
            var request = context.Request;

            switch (request.Url!.AbsolutePath) {
                case "/deploy":
                    await HandleDeployRequest(context);
                    return true;
                case "/login":
                    HandleLoginRequest(context);
                    return true;
                case "/info":
                    HandleInfoRequest(context);
                    return true;
                default:
                    return false;
            }
        }

        private static async Task HandleDeployRequest(HttpListenerContext context) {
            var request = context.Request;
            string exeName = request.QueryString.Get("execName") ?? "";
            if (string.IsNullOrEmpty(exeName)) {
                SendResponse(context.Response, CreateErrorResponse("Invalid executable name"));
                return;
            }
            string version = request.QueryString.Get("version") ?? "";

            IPEndPoint remoteIP = context.Request.RemoteEndPoint;
            Log.Debug("Remote IP: {RemoteIP}", remoteIP);
            bool portOpen = await IsTcpPortOpenAsync(remoteIP.Address.ToString(), 80);
            if (!portOpen) {
                SendResponse(context.Response, CreateErrorResponse($"Port 80 not open on {remoteIP.Address}"));
                return;
            }

            string responseString = await Install(exeName, version, "http://" + remoteIP.Address);
            Log.Information("Install response: {Response}", responseString);
            SendResponse(context.Response, responseString);
            Log.Information("Handled deploy request for {ExeName} version {Version} from {RemoteAddr}", exeName, version, remoteIP.Address);
        }

        private static void HandleLoginRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string[]? usernames = request.QueryString.GetValues("username");
            string[]? passwords = request.QueryString.GetValues("password");
            if (usernames == null || usernames.Length == 0 || passwords == null || passwords.Length == 0) {
                SendResponse(response, 500, "error params");
                return;
            }
            var token = GenerateToken();
            tokens.Add(token, DateTimeOffset.Now.ToUnixTimeSeconds());
            response.Headers.Add("token", token);
            SendResponse(response, 200, token);
        }

        private static void HandleInfoRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string[]? t = request.QueryString.GetValues("token");
            if (t == null || t.Length == 0 || t[0].Length == 0) {
                SendResponse(response, 500, "error params");
                return;
            }
            if (!tokens.ContainsKey(t[0])) {
                SendResponse(response, 500, "not exists");
                return;
            }
            if (DateTimeOffset.Now.ToUnixTimeSeconds() - tokens[t[0]] > 300) {
                SendResponse(response, 500, "token expired");
                return;
            }
            SendResponse(response, 200, "ok");
        }

        private static Task ServeStaticContent(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string absolutePath = request.Url!.AbsolutePath;
            string filePath = ResolveFilePath(absolutePath);

            if (File.Exists(filePath)) {
                ServeFile(response, filePath);
                return Task.CompletedTask;
            }

            string directoryPath = Directory.Exists(filePath) ? filePath : AppConfig.BinPath;

            string indexPath = filePath + "\\" + AppConfig.DefaultIndex;
            if (File.Exists(indexPath)) {
                ServeFile(response, indexPath, "text/html; charset=utf-8");
                return Task.CompletedTask;
            }

            ServeDirectoryListing(response, absolutePath, directoryPath);
            return Task.CompletedTask;
        }

        private static string ResolveFilePath(string absolutePath) {
            string filePath = $"{AppConfig.BinPath}\\{absolutePath}";

            if (filePath.IndexOf("/sirius/dev/master") > -1) {
                const string siriusDevDir = "D:\\workdata\\sirius-client-dev\\bili-tools\\master-tools\\master_output";
                filePath = Path.GetExtension(filePath) == ".zip"
                    ? $"{siriusDevDir}\\{Path.GetFileName(filePath)}"
                    : siriusDevDir;
            }

            return filePath;
        }

        private static void ServeFile(HttpListenerResponse response, string filePath, string? contentType = null) {
            if (contentType == null) {
                contentType = IsBinaryFile(filePath) || Path.GetExtension(filePath) == ".bat"
                    ? "application/octet-stream"
                    : "text/html; charset=utf-8";
            }

            response.ContentType = contentType;
            using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                response.ContentLength64 = fs.Length;
                fs.CopyTo(response.OutputStream);
            }
            response.OutputStream.Close();
        }

        private static void ServeDirectoryListing(HttpListenerResponse response, string basePath, string directoryPath) {
            response.ContentType = "text/html; charset=utf-8";
            DirectoryInfo info = new DirectoryInfo(directoryPath);
            StringBuilder sb = new StringBuilder();

            foreach (var item in info.GetFileSystemInfos().OrderByDescending(f => f.LastWriteTime).ToArray()) {
                string sizeStr = "-";
                if (item is FileInfo file) {
                    sizeStr = file.Length.ToString("N0");
                }
                string href = basePath + "/" + item.Name;
                sb.AppendLine($"<div class=\"directory-header\"><div class=\"name\"><a href=\"{href.Replace("//", "/")}\">{item.Name}</a></div><div class=\"size\">{sizeStr}</div><div class=\"modified\">{item.LastWriteTime.ToString()}</div></div>");
            }

            string html = BuildDirectoryListingHtml(sb.ToString());
            byte[] buffer = Encoding.UTF8.GetBytes(html);
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        private static string BuildDirectoryListingHtml(string rows) {
            return $@"
<style>
.directory {{
    font-family: monospace;
    width: 100%;
    max-width: 800px;
}}

.directory-header {{
    display: grid;
    grid-template-columns: 3fr 1fr 1.5fr;
    padding: 8px;
    font-weight: bold;
    border-bottom: 1px dashed #ccc;
}}

.directory-row {{
    display: grid;
    grid-template-columns: 3fr 1fr 1.5fr;
    padding: 6px 8px;
    border-bottom: 1px dashed #eee;
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
        <div class=""size"">大小(byte)</div>
        <div class=""modified"">修改时间</div>
    </div>
 {rows}
</div>";
        }

        public static bool IsBinaryFile(string filePath, int sampleSize = 4096, double nonTextThreshold = 0.3) {
            if (!File.Exists(filePath)) {
                throw new FileNotFoundException("文件不存在", filePath);
            }
            using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                int size = (int)Math.Min(fs.Length, sampleSize);
                if (size == 0) return false;   // 空文件视为文本
                byte[] buffer = new byte[size];
                fs.Read(buffer, 0, size);
                int nonTextCount = 0;
                foreach (byte b in buffer) {
                    // 空字节是二进制文件的强烈信号
                    if (b == 0x00) {
                        return true;
                    }
                    // 非可打印字符（不包括换行、回车、制表符等常见文本控制字符）
                    if (b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) {
                        nonTextCount++;
                    }
                }
                double ratio = (double)nonTextCount / size;
                return ratio > nonTextThreshold;
            }
        }

        private static async Task<string> HandleZipInstall(string urlName, string domainDownload, PathInfo info, string version) {
            string url = $"{domainDownload}/{urlName}";
            Log.Information("Handling zip install for {UrlName} from {Url}", urlName, url);
            await HandleExeInstall(url, info, version);
            Log.Debug("Downloaded zip file for {UrlName}, now processing...", urlName);
            string fullPath, nssmPath, data;
            switch (urlName) {
                case "AnonTokyoSiriusServerCbor.zip":
                    string cborPath = Path.Combine(AppConfig.BinPath, AppConfig.CborDirectoryName);
                    Log.Information("Extracting CBOR to {CborPath}", cborPath);
                    EnsureDirectoryDeleted(cborPath);
                    Log.Information("Extracting {BinPath} to {DestPath}", info.binPath, AppConfig.BinPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    Log.Information("CBOR extraction completed for {UrlName}", urlName);
                    return CreateSuccessResponse();
                case "AnonTokyoConfig.zip":
                    Log.Information("Extracting config to {BinPath}", AppConfig.BinPath);
                    EnsureDirectoryDeleted(Path.Combine(AppConfig.BinPath, AppConfig.AtConfigDirectoryName));
                    Log.Information("Extracting {BinPath} to {DestPath}", info.binPath, AppConfig.BinPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    Log.Information("Config extraction completed for {UrlName}", urlName);
                    return CreateSuccessResponse();
                case "AnontokyoDocs.zip":
                    string docsPath = Path.Combine(AppConfig.BinPath, "docs");
                    EnsureDirectoryDeleted(docsPath);
                    Log.Information("Extracting {BinPath} to {DestPath}", info.binPath, AppConfig.BinPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    Log.Information("Docs extraction completed for {UrlName}", urlName);
                    return CreateSuccessResponse();
                case "Mysql.zip":
                    string mysqlServerName = "AnonTokyoMysql";
                    string mysqlDir = $"{AppConfig.BinPath}\\mysql";
                    if (!Directory.Exists(mysqlDir)) {
                        ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    }
                    var result = FindService(mysqlServerName);
                    if (result.serviceExists) {
                        StartServiceIfStopped(mysqlServerName);
                        return CreateSuccessResponse();
                    }
                    Log.Information("Initializing MySQL data directory at {MysqlDir}", mysqlDir);
                    string dataDir = $"{mysqlDir}\\data";
                    var resultData = (RunProcess($"{mysqlDir}\\bin\\mysqld", "--initialize --console"));
                    if (!Directory.Exists(dataDir) && resultData.Item1 != 0) {
                        return CreateErrorResponse("failed to initialize");
                    }

                    Log.Debug("MySQL initialization output: {Output}", resultData.Item3);
                    Match match = Regex.Match(resultData.Item3, @"A temporary password is generated for root@localhost:(.+)");
                    if (!match.Success) {
                        Log.Error("Failed to extract temporary password from mysqld output");
                        return CreateErrorResponse(resultData.Item3);
                    }
                    string tempPassword = match.Groups[1].Value.Trim();

                    Log.Information("Registering MySQL service with NSSM");
                    fullPath = $"{mysqlDir}\\bin\\mysqld.exe";
                    nssmPath = GetNssmPath();
                    data = RegisterWindowsService(nssmPath, mysqlServerName, fullPath, $"--defaults-file=\"{mysqlDir}\\bin\\my.ini\"");
                    if (!string.IsNullOrEmpty(data)) {
                        return CreateErrorResponse(data);
                    }
                    Log.Information("Starting MySQL service and waiting for it to be running");
                    StartServiceAndWait(mysqlServerName);

                    // 等待3306端口开放，表示MySQL服务已完全启动
                    bool ready = PortWatcher.WaitForPort("localhost", 3306, timeoutSeconds: 60);
                    if (!ready) {
                        Log.Error("MySQL did not start within the expected time");
                        return CreateErrorResponse("MySQL did not start within the expected time.");
                    }

                    // 清空mysql密码，允许空密码登录
                    Log.Information("Resetting MySQL root password");
                    RunProcess($"{mysqlDir}\\bin\\mysql", $"-u root --connect-expired-password -p\"{tempPassword}\" -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '';\"");

                    Log.Information("Granting remote access to MySQL root user");
                    RunProcess($"{mysqlDir}\\bin\\mysql", $"-u root -e \"create USER 'root'@'%' IDENTIFIED BY '';\"");
                    RunProcess($"{mysqlDir}\\bin\\mysql", $"-u root -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;\"");

                    return CreateSuccessResponse();
                case "Redis.zip":
                    string redisServerName = "AnonTokyoRedis";
                    string redisDir = $"{AppConfig.BinPath}\\redis";
                    StopServiceIfRunning(redisServerName);
                    fullPath = $"{redisDir}\\redis-server.exe";
                    nssmPath = GetNssmPath();

                    if (!Directory.Exists(redisDir)) {
                        Log.Information("Extracting Redis to {RedisDir}", redisDir);
                        ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    }
                    Log.Information("Checking if Redis service already exists");
                    var result2 = FindService(redisServerName);
                    if (result2.serviceExists) {
                        Log.Information("Redis service already exists, starting if stopped");
                        StartServiceIfStopped(redisServerName);
                        Log.Information("Redis service is running");
                        return CreateSuccessResponse();
                    }
                    Log.Information("Registering Redis service with NSSM");
                    data = RegisterWindowsService(nssmPath, redisServerName, fullPath, $"\"{redisDir}\\redis.windows.conf\"");
                    if (!string.IsNullOrEmpty(data)) {
                        Log.Error("Failed to register Redis service: {Error}", data);
                        return CreateErrorResponse(data);
                    }
                    StartServiceAndWait(redisServerName);
                    return CreateSuccessResponse();
            }
            return "";
        }

        public static int Run(string[] args) {
            InitializeLogger();
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
                    Log.Error("Install daemon failed: {Error}", result);
                }
            });

            netinfo.SetAction((@params) => {
                PrintNetworkInfo();
            });

            root.Subcommands.Add(service);
            service.Subcommands.Add(daemon);
            service.Subcommands.Add(netinfo);
            service.Subcommands.Add(run);

            return root.Parse(args).Invoke();
        }

        public static async Task StartService(CancellationToken cancellationToken = default) {
            using HttpListener listener = new HttpListener();
            listener.Prefixes.Add(AppConfig.DomainExpose);
            listener.Start();
            Log.Information("Listen: {Domain}", AppConfig.DomainExpose);

            try {
                while (!cancellationToken.IsCancellationRequested) {
                    HttpListenerContext context = await listener.GetContextAsync();
                    _ = Task.Run(() => HandleRequestAsync(context), cancellationToken);
                }
            } catch (OperationCanceledException) {
                Log.Information("Service shutdown requested");
            } catch (HttpListenerException ex) when (ex.ErrorCode == 995) {
                Log.Information("Listener closed during shutdown");
            } finally {
                listener.Stop();
                Log.Information("Listener stopped");
            }
        }

        private static async Task HandleRequestAsync(HttpListenerContext context) {
            try {
                await ProcessRequest(context);
            } catch (Exception ex) {
                Log.Error(ex, "Request processing error");
                try {
                    SendResponse(context.Response, CreateErrorResponse($"Request processing error: {ex.Message}"));
                } catch (Exception responseEx) {
                    Log.Error(responseEx, "Failed to send error response");
                }
            }
        }

        public static string InstallDaemon() {
            //try {
            string executablePath = Assembly.GetExecutingAssembly().Location;
            StopServiceIfRunning(AppConfig.ServiceName);
            UnregisterServiceIfExists(AppConfig.ServiceName);

            if (!Directory.Exists(AppConfig.BinPath)) {
                Directory.CreateDirectory(AppConfig.BinPath);
            }

            string destFile = Path.Combine(AppConfig.BinPath, Path.GetFileName(executablePath));
            CopyFileWithBackup(executablePath, destFile);

            string nssmPath = GetNssmPath();
            string result = RegisterWindowsService(nssmPath, AppConfig.ServiceName, destFile, "service run");
            if (!string.IsNullOrEmpty(result)) {
                return CreateErrorResponse(result);
            }

            StartServiceAndWait(AppConfig.ServiceName);
            return "";
            //} catch (Exception ex) {
            //    return CreateErrorResponse($"服务安装失败: {ex.Message}");
            //}
        }

        private static void StopServiceIfRunning(string serviceName) {
            var result = FindService(serviceName);
            if (result.serviceExists) {
                if (result.specificService.Status == ServiceControllerStatus.Running ||
                    result.specificService.Status == ServiceControllerStatus.Paused) {
                    result.specificService.Stop();
                    result.specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }
            }
        }

        private static (ServiceController specificService, bool serviceExists) FindService(string serviceName) {
            ServiceController specificService = new ServiceController(serviceName);
            bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));
            return (specificService, serviceExists);
        }

        private static void UnregisterServiceIfExists(string serviceName) {
            bool serviceExists = ServiceController.GetServices()
                .Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));

            if (serviceExists) {
                string nssmPath = GetNssmPath();
                string data = UnregisterWindowsService(nssmPath, serviceName);
                if (!string.IsNullOrEmpty(data)) {
                    throw new Exception(data);
                }
            }
        }

        private static void CopyFileWithBackup(string source, string destination) {
            EnsureFileDeleted(destination);
            File.Copy(source, destination);
        }

        private static void EnsureFileDeleted(string filePath) {
            if (File.Exists(filePath)) {
                File.Delete(filePath);
            }
        }

        private static void StartServiceAndWait(string serviceName) {
            ServiceController specificService = new ServiceController(serviceName);
            specificService.Start();
            specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(AppConfig.ProcessTimeout));
        }

        public static void PrintNetworkInfo() {
            Log.Information("Network Information");

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
                    subnetMask = GetSubnetMaskForIP(address)?.ToString() ?? "";
                }
            }

            Log.Information("IP Address:  {IP}", ipAddress);
            Log.Information("Net Mask:    {Mask}", subnetMask);
        }

        private static void PrintDnsServers() {
            foreach (var dns in GetAllDnsServers()) {
                Log.Information("DNS Server:  {DNS}", dns);
            }
        }

        private static void PrintProxyInfo() {
            var proxyInfo = SystemProxyInfo.GetFromRegistry();
            Log.Information("Proxy Enabled:  {Enabled}", proxyInfo.Enabled);
            Log.Information("Proxy Server:   {Server}", proxyInfo.Server);
        }



        public static void SendResponse(HttpListenerResponse response, string responseString) {
            if (string.IsNullOrEmpty(responseString)) {
                response.OutputStream.Close();
                return;
            }
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
                {"interval", ((int)((DateTime.Now.Subtract(StartDate)).TotalMilliseconds)).ToString() + "ms"},
            };
            return $"{JsonConvert.SerializeObject(responseDict)}\n";
        }

        public async static Task<string> Install(string urlName, string version, string domainDownload) {
            //try {
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
                        Log.Information("Handling zip install for {UrlName}", urlName);
                        return await HandleZipInstall(urlName, domainDownload, info, version);
                    default:
                        return CreateErrorResponse("Unsupported file type");
                }
            });
            //} catch (Exception ex) {
            //    return CreateErrorResponse($"操作失败: {ex.Message}");
            //}
        }

        private static async Task<string> HandleExeInstall(string url, PathInfo info, string version) {
            // 检查版本
            if (!FileMapService.ContainsKey(Path.GetFileName(url))) {
                return CreateErrorResponse("Invalid executable");
            }
            string binDirPath = Path.GetDirectoryName(info.binPath)!;
            string filename = Path.GetFileName(info.binPath);
            string tempDir = $"{binDirPath}\\temp";

            Log.Information("Preparing to install {Filename} from {Url} with version {Version}", filename, url, version);
            if (!Directory.Exists(tempDir)) {
                Directory.CreateDirectory(tempDir);
            }
            Log.Debug("Checking for existing versions of {Filename} in {BinDirPath}", filename, binDirPath);
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
            Log.Information("Selected version for {Filename}: {Version}", filename, version);
            // 如果版本号不为 -1，检查当前目录下是否存在对应版本的文件，如果存在则直接复制到目标位置
            string versionFilename = $"{binDirPath}\\history\\{filename}-{version}{Path.GetExtension(info.binPath)}";
            string? versionDir = Path.GetDirectoryName(versionFilename);
            if (!Directory.Exists(versionDir)) {
                Directory.CreateDirectory(versionDir!);
            }
            if (File.Exists(versionFilename)) {
                if (File.Exists(info.binPath)) {
                    File.Delete(info.binPath);
                }
                File.Copy(versionFilename, info.binPath);
                return CreateSuccessResponse();
            }

            if (version == "-1") {
                return CreateErrorResponse("empty version");
            }
            Log.Information("No existing version found for {Filename} with version {Version}, proceeding to download from {Url}", filename, version, url);
            // 下载新版本
            string destTempFile = $"{tempDir}\\{filename}";
            if (await DownloadFileAsync(url, destTempFile)) {
                if (File.Exists(info.binPath)) {
                    File.Move(info.binPath, versionFilename);
                }
                File.Move(destTempFile, info.binPath);

                DirectoryInfo directoryInfo = new DirectoryInfo(tempDir) {
                    Attributes = FileAttributes.Normal,
                };
                directoryInfo.Delete(true);
            }
            return CreateSuccessResponse();
        }


        private static void EnsureDirectoryDeleted(string path) {
            if (Directory.Exists(path)) {
                Directory.Delete(path, true);
            }
        }

        public static async Task<string> RestartService(string urlName, Func<Task<string>> handler) {
            if (string.IsNullOrEmpty(FileMapService[urlName])) {
                Log.Debug("No associated service for {UrlName}, skipping service restart", urlName);
                string result2 = await handler();
                Log.Debug("Handler result for {UrlName}: {Result}", urlName, result2);
                if (!string.IsNullOrEmpty(result2)) {
                    return result2;
                }
                return CreateSuccessResponse();
            }
            Log.Information("Restarting service for {UrlName}", urlName);
            string serviceName = FileMapService[urlName];
            Log.Information("Stopping service {ServiceName} if it is running", serviceName);
            StopServiceIfRunning(serviceName);

            string result = await handler();
            if (Path.GetExtension(urlName) == ".exe" && !ServiceExists(serviceName)) {
                string fullPath = Path.Combine(AppConfig.BinPath, Path.GetFileName(urlName));
                string nssmPath = GetNssmPath();
                Log.Information("Registering service {ServiceName} with NSSM at {NssmPath} for executable {FullPath}", serviceName, nssmPath, fullPath);
                string data = RegisterWindowsService(nssmPath, serviceName, fullPath);
                if (!string.IsNullOrEmpty(data)) {
                    return CreateErrorResponse(data);
                }
            }
            Log.Information("Starting service {ServiceName} if it exists", serviceName);
            StartServiceIfStopped(serviceName);
            return result;
        }

        private static bool ServiceExists(string serviceName) {
            return ServiceController.GetServices()
                .Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));
        }

        private static void StartServiceIfStopped(string serviceName) {
            ServiceController service = new ServiceController(serviceName);
            if (service.Status == ServiceControllerStatus.Stopped) {
                Log.Information("Starting service {ServiceName}", serviceName);
                service.Start();
                service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(AppConfig.ProcessTimeout));
                Log.Information("Service {ServiceName} is now running", serviceName);
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

        public static string FormatResponse(string code = "200", string message = "Service update successfully.") {
            return CreateResponse(code, message);
        }

        public async static Task<bool> DownloadFileAsync(string url, string filePath) {
            using var handler = new HttpClientHandler();
            using var client = new HttpClient(handler);
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0");
            client.Timeout = TimeSpan.FromMilliseconds(AppConfig.DefaultTimeout);
            Log.Information("Starting download from {Url} to {FilePath}", url, filePath);
            using (var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
            using (Stream responseStream = await response.Content.ReadAsStreamAsync())
            using (FileStream fileStream = File.Create(filePath)) {
                response.EnsureSuccessStatusCode();
                byte[] buffer = new byte[4096];
                int bytesRead;
                while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                    await fileStream.WriteAsync(buffer, 0, bytesRead);
                }
            }
            return true;
        }

        public class PathInfo {
            public required string binPath, filename, logPath;
        }

        public static string UnregisterWindowsService(string nssmPath, string serviceName) {
            if (!File.Exists(nssmPath)) {
                return CreateErrorResponse($"nssm.exe not found: {nssmPath}");
            }

            string args = $"remove \"{serviceName}\" confirm";
            if ((RunProcess(nssmPath, args)).Item1 != 0) {
                return CreateErrorResponse("Failed to uninstall service");
            }
            return "";
        }

        public static string RegisterWindowsService(string nssmPath, string serviceName, string executablePath, string arguments = "", string startType = "SERVICE_AUTO_START") {
            if (!File.Exists(nssmPath)) {
                Log.Error("NSSM executable not found at path: {NssmPath}", nssmPath);
                return CreateErrorResponse($"nssm.exe not found: {nssmPath}");
            }

            if (!File.Exists(executablePath)) {
                Log.Error("Executable not found at path: {ExePath}", executablePath);
                return CreateErrorResponse($"Executable not found: {executablePath}");
            }

            //try {
            string installArgs = BuildInstallArgs(serviceName, executablePath, arguments);
            if (!TryRunNssmCommand(nssmPath, installArgs)) {
                return CreateErrorResponse("Failed to install service");
            }

            SetServiceProperties(nssmPath, serviceName, executablePath, startType);
            return "";
            //} catch (Exception ex) {
            //    return CreateErrorResponse($"Service registration failed: {ex.Message}");
            //}
        }

        private static string BuildInstallArgs(string serviceName, string executablePath, string arguments) {
            string args = $"install \"{serviceName}\" \"{executablePath}\"";
            if (!string.IsNullOrWhiteSpace(arguments)) {
                args += $" {arguments}";
            }
            return args;
        }

        private static void SetServiceProperties(string nssmPath, string serviceName, string executablePath, string startType) {
            RunProcess(nssmPath, $"set \"{serviceName}\" DisplayName \"{serviceName}\"");
            RunProcess(nssmPath, $"set \"{serviceName}\" Description \"{serviceName}\"");

            if (Path.GetExtension(executablePath) == ".exe") {
                SetServiceLogPaths(nssmPath, serviceName, executablePath);
            }

            if (!string.IsNullOrWhiteSpace(startType)) {
                RunProcess(nssmPath, $"set \"{serviceName}\" Start {startType}");
            }

            RunProcess(nssmPath, $"set \"{serviceName}\" AppRestartDelay 5000");
            RunProcess(nssmPath, $"set \"{serviceName}\" Environment \"SERVER_PORT=8080\"");
        }

        private static void SetServiceLogPaths(string nssmPath, string serviceName, string executablePath) {
            string logPath = Path.Combine(
                Path.GetDirectoryName(executablePath)! + "\\logs\\",
                Path.GetFileNameWithoutExtension(executablePath) + ".log");

            string? logDir = Path.GetDirectoryName(logPath);
            if (!Directory.Exists(logDir)) {
                Directory.CreateDirectory(logDir!);
            }

            if (!File.Exists(logPath) && Path.GetExtension(executablePath) == ".exe") {
                File.Create(logPath).Dispose();
            }

            RunProcess(nssmPath, $"set \"{serviceName}\" AppStdin \"{logPath}\"");
            RunProcess(nssmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            RunProcess(nssmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
        }

        private static bool TryRunNssmCommand(string nssmPath, string arguments) {
            return (RunProcess(nssmPath, arguments)).Item1 == 0;
        }

        public static (int, string, string) RunProcess(string nssmPath, string arguments) {
            var startInfo = new ProcessStartInfo {
                FileName = nssmPath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            Log.Debug("Running command: {Command} {Args}", nssmPath, arguments);

            //【重點：服務執行直接移除runas/needsAdmin判斷，LocalSystem本身全權限】
            //刪除所有 if(!IsAdministrator()) runas相關程式碼

            try {
                using (var process = Process.Start(startInfo)) {
                    if (process == null) return (-2, "", "啟動進程失敗");
                    process.WaitForExit();
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    Log.Debug("Exit:{ExitCode},Out:{Output},Err:{Error}", process.ExitCode, output, error);
                    return (process.ExitCode, output, error);
                }
            } catch (Exception ex) {
                return (-99, "", ex.Message);
            }
        }

        public static bool IsAdministrator() {
            var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }

        public static string RunShellCommand(string command) {
            //try {
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
            //} catch (Exception ex) {
            //    return $"Command execution failed: {ex.Message}";
            //}
        }

        public static string GetNssmPath() {
            return AppConfig.BinPath + "\\nssm.exe";
        }

        public static async Task<bool> IsTcpPortOpenAsync(string host, int port, int timeoutMilliseconds = 3000) {
            using (TcpClient client = new TcpClient()) {
                //try {
                var connectTask = client.ConnectAsync(host, port);
                var completedTask = await Task.WhenAny(connectTask, Task.Delay(timeoutMilliseconds));
                if (completedTask == connectTask) {
                    await connectTask;
                    return true;
                }
                return false;
                //} catch {
                //    return false;
                //}
            }
        }

        public static IPAddress? GetSubnetMaskForIP(IPAddress ip) {
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
            public string Code { get; set; } = "";
            public string Data { get; set; } = "";
            public string Message { get; set; } = "";
        }

        private static void SendResponse(HttpListenerResponse response, Int32 code, string responseString) {
            var data = new Result {
                Code = $"{code}",
                Data = responseString,
            };

            byte[] buffer = Encoding.UTF8.GetBytes($"{JsonConvert.SerializeObject(data)}\n");
            response.StatusCode = code;
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
        public string Server { get; set; } = "";
        public string Override { get; set; } = "";
        public bool AutoDetect { get; set; }
        public string AutoConfigUrl { get; set; } = "";
        public static SystemProxyInfo GetFromRegistry() {
            var info = new SystemProxyInfo();
            const string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
            using (RegistryKey? registryKey = Registry.CurrentUser.OpenSubKey(keyPath)) {
                if (registryKey != null) {
                    info.Enabled = Convert.ToInt32(registryKey.GetValue("ProxyEnable", 0)) == 1;
                    info.Server = registryKey.GetValue("ProxyServer", "")?.ToString() ?? "";
                    info.Override = registryKey.GetValue("ProxyOverride", "")?.ToString() ?? "";
                    info.AutoDetect = Convert.ToInt32(registryKey.GetValue("AutoDetect", 0)) == 1;
                    info.AutoConfigUrl = registryKey.GetValue("AutoConfigURL", "")?.ToString() ?? "";
                }
            }
            return info;
        }
    }

    public static class PortWatcher {
        /// <summary>
        /// 等待指定主机的端口变为监听状态（同步方式）
        /// </summary>
        /// <param name="host">主机名或IP地址</param>
        /// <param name="port">端口号</param>
        /// <param name="timeoutSeconds">总超时时间（秒）</param>
        /// <param name="retryIntervalMilliseconds">每次重试间隔（毫秒）</param>
        /// <returns>超时前端口开放返回 true，否则返回 false</returns>
        public static bool WaitForPort(string host, int port, int timeoutSeconds = 30, int retryIntervalMilliseconds = 1000) {
            var startTime = DateTime.Now;
            var timeout = TimeSpan.FromSeconds(timeoutSeconds);

            while (DateTime.Now - startTime < timeout) {
                if (IsPortOpen(host, port, retryIntervalMilliseconds / 2)) // 单次检测超时设短一些
                {
                    return true;
                }
                Thread.Sleep(retryIntervalMilliseconds);
            }
            return false;
        }

        /// <summary>
        /// 异步等待端口开放（推荐，避免阻塞线程）
        /// </summary>
        public static async Task<bool> WaitForPortAsync(string host, int port, int timeoutSeconds = 30, int retryIntervalMilliseconds = 1000, CancellationToken cancellationToken = default) {
            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

            while (!cts.Token.IsCancellationRequested) {
                if (await IsPortOpenAsync(host, port, retryIntervalMilliseconds / 2)) {
                    return true;
                }
                await Task.Delay(retryIntervalMilliseconds, cts.Token);
            }
            return false;
        }

        // 单次检测端口是否开放（同步）
        private static bool IsPortOpen(string host, int port, int timeoutMs) {
            try {
                var tcpClient = new TcpClient();
                var task = tcpClient.ConnectAsync(host, port);
                if (task.Wait(timeoutMs) && tcpClient.Connected)
                    return true;
                return false;
            } catch {
                return false;
            }
        }

        // 单次检测端口是否开放（异步）
        private static async Task<bool> IsPortOpenAsync(string host, int port, int timeoutMs) {
            try {
                var tcpClient = new TcpClient();
                var connectTask = tcpClient.ConnectAsync(host, port);
                var timeoutTask = Task.Delay(timeoutMs);
                var completedTask = await Task.WhenAny(connectTask, timeoutTask);
                if (completedTask == connectTask && tcpClient.Connected) {
                    await connectTask; // 捕获可能的异常
                    return true;
                }
                return false;
            } catch {
                return false;
            }
        }
    }
}