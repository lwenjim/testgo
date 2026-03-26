using System;
using System.Collections.Generic;
using System.CommandLine;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32;
using Newtonsoft.Json;

namespace ManageAnonTokyo {
    public static class AppConfig {
        public const string BinPath = "D:\\bin\\bin";
        public const string DocsPath = "C:\\inetpub\\wwwroot";
        public const string DomainExpose = "http://*:8082/deploy/";
        public const string ServiceName = "AnonTokyoManage";
        public const string CborDirectoryName = "mastercbor";
        public const int DefaultTimeout = 60000;
        public const int ProcessTimeout = 30;
    }

    public class InstallService {
        private const string SuccessCode = "200";
        private const string ErrorCode = "500";
        private const string SuccessMessage = "Service update successfully.";

        public readonly static DateTime StartDate = DateTime.Now;

        private static readonly Dictionary<string, string> FileMapService = new Dictionary<string, string>() {
            {"AnontokyoServer.exe", "AnonTokyoServer"},
            {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
            {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer"},
            {"TestGo.exe", "AnonTokyoTestGo"},
            {"AnontokyoDocs.zip", ""},
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

        public static async Task StartService() {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(AppConfig.DomainExpose);
            listener.Start();
            Console.WriteLine($"Listen: {AppConfig.DomainExpose}");
            try {
                while (true) {
                    HttpListenerContext context = await listener.GetContextAsync();
                    _ = ProcessRequest(context); // Fire and forget
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
            ServiceController specificService = new ServiceController(serviceName);
            bool serviceExists = ServiceController.GetServices()
                .Any(s => s.ServiceName.Equals(serviceName, StringComparison.OrdinalIgnoreCase));

            if (serviceExists) {
                if (specificService.Status == ServiceControllerStatus.Running ||
                    specificService.Status == ServiceControllerStatus.Paused) {
                    specificService.Stop();
                    specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }
            }
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

        private static void SafeDeleteFile(string path) {
            if (File.Exists(path)) {
                File.Delete(path);
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

        public static async Task ProcessRequest(HttpListenerContext context) {
            try {
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
            } catch (Exception ex) {
                Response(context.Response, CreateErrorResponse($"Request processing error: {ex.Message}"));
            }
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

        private static async Task<string> HandleZipInstall(string urlName, string domainDownload, PathInfo info, string version) {
            string url = $"{domainDownload}/{urlName}";
            await HandleExeInstall(url, info, version);
            switch (urlName) {
                case "AnonTokyoSiriusServerCbor.zip":
                    string cborPath = Path.Combine(AppConfig.BinPath, AppConfig.CborDirectoryName);
                    SafeDeleteDirectory(cborPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    break;

                case "AnontokyoDocs.zip":
                    string docsPath = Path.Combine(AppConfig.DocsPath, "docs");
                    SafeDeleteDirectory(docsPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.DocsPath);
                    return CreateSuccessResponse();
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
                return await handler();
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
            if (!string.IsNullOrEmpty(RunNssmCommand(nssmPath, args))) {
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
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" DisplayName \"{serviceName}\"");
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" Description \"{serviceName}\"");

            if (Path.GetExtension(executablePath) == ".exe") {
                SetServiceLogPaths(nssmPath, serviceName, executablePath);
            }

            if (!string.IsNullOrWhiteSpace(startType)) {
                RunNssmCommand(nssmPath, $"set \"{serviceName}\" Start {startType}");
            }

            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppRestartDelay 5000");
        }

        private static void SetServiceLogPaths(string nssmPath, string serviceName, string executablePath) {
            string logPath = Path.Combine(
                Path.GetDirectoryName(executablePath),
                Path.GetFileNameWithoutExtension(executablePath) + ".log");

            if (!File.Exists(logPath) && Path.GetExtension(executablePath) == ".exe") {
                File.Create(logPath).Dispose();
            }

            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStdin \"{logPath}\"");
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            RunNssmCommand(nssmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
        }

        private static bool TryRunNssmCommand(string nssmPath, string arguments) {
            return string.IsNullOrEmpty(RunNssmCommand(nssmPath, arguments));
        }

        public static string RunNssmCommand(string nssmPath, string arguments) {
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
                        return "Process failed to start";
                    }

                    process.WaitForExit();

                    if (!needsAdmin) {
                        string output = process.StandardOutput.ReadToEnd();
                        string error = process.StandardError.ReadToEnd();

                        if (!string.IsNullOrEmpty(output)) {
                            Console.WriteLine(output);
                        }
                        if (!string.IsNullOrEmpty(error)) {
                            return $"Error: {error}";
                        }
                    }

                    if (process.ExitCode > 0) {
                        return $"Command failed with exit code: {process.ExitCode}";
                    }
                }
            } catch (Exception ex) {
                return $"Command execution failed: {ex.Message}";
            }
            return "";
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
            return RunCommand("where nssm").Trim();
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
