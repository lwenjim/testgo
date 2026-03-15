using Microsoft.Win32;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
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

namespace ManageAnonTokyo {
    public class InstallService {

        readonly static DateTime StartDate = DateTime.Now;

        public static string GetDomainExpose() {
            return "http://*:8082/deploy/";
        }

        public static string GetBinPath() {
            return "D:\\bin\\bin";
        }

        public static async Task StartService() {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(GetDomainExpose());
            listener.Start();
            Console.WriteLine($"lissten: {GetDomainExpose()} port");
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
            IPEndPoint ip = context.Request.RemoteEndPoint;
            bool isOpen = await IsTcpPortOpenAsync(ip.Address.ToString(), 80);
            if (!isOpen) {
                Response(context.Response, $"not open {ip.Address.ToString()}:80 ");
                return;
            }
            string responseString = await Install(exeName, "http://" + ip.Address.ToString());
            Response(context.Response, responseString);
        }

        static void Response(HttpListenerResponse response, string responseString) {
            byte[] buffer = Encoding.UTF8.GetBytes(responseString);
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        public async static Task<string> Install(string urlName, string DomainDownload) {
            try {
                Dictionary<string, string> fileMapService = new Dictionary<string, string>() {
                    {"AnontokyoServer.exe", "AnonTokyoServer"},
                    {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
                    {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer" },
                };
                if (Path.GetExtension(urlName) == ".exe" && !fileMapService.ContainsKey(urlName)) {
                    return Response("500", $"error params, info:{urlName}");
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
                            if (Directory.Exists(GetBinPath() + "\\mastercbor")) {
                                Directory.Delete(GetBinPath() + "\\mastercbor", true);
                            }
                            ZipFile.ExtractToDirectory(info.binPath, GetBinPath());
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

        public static string InstallDaemon() {
            string path = Assembly.GetExecutingAssembly().Location;
            string serverName = "AnonTokyoManage";
            ServiceController specificService = new ServiceController(serverName);
            bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(serverName, StringComparison.OrdinalIgnoreCase));
            if (serviceExists && (specificService.Status == ServiceControllerStatus.Running || specificService.Status == ServiceControllerStatus.Paused)) {
                specificService.Stop();
                specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
            }
            if (serviceExists) {
                string data = UnRegisterWindowService(GetNssmPath(), serverName);
                if (data.Length > 0) {
                    return Response("500", data);
                }
            }
            string destFile = $"{GetBinPath()}\\{Path.GetFileName(path)}";
            if (File.Exists(destFile)) {
                File.Delete(destFile);
            }
            File.Copy(path, destFile);
            string result = RegisterWindowService(GetNssmPath(), serverName, destFile, "service run");
            if (result.Length > 0) {
                return Response("500", result);
            }
            specificService.Start();
            specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
            return "";
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
            if (!serviceExists && Path.GetExtension(urlName) == ".exe") {
                string fullName = $"{GetBinPath()}\\{Path.GetFileName(urlName)}";
                string serviceName = fileMapService[urlName];
                string data = RegisterWindowService(GetNssmPath(), serviceName, fullName);
                if (data.Length > 0) {
                    return Response("500", data);
                }
            }
            if (specificService.Status == ServiceControllerStatus.Stopped) {
                specificService.Start();
                specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
            }
            return Response();
        }

        public static PathInfo GetBinPathFilenameAndLogname(string urlName) {
            string binPath = $"{GetBinPath()}\\{urlName}";
            if (File.Exists(binPath)) {
                File.Delete(binPath);
            }
            string filename = Path.GetFileNameWithoutExtension(binPath);
            string logPath = string.Format($"{GetBinPath()}\\{0}.log", filename);
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
            return $"{JsonConvert.SerializeObject(scores)}\n";
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

        public static string UnRegisterWindowService(string nPath, string serviceName) {
            if (!File.Exists(nPath)) {
                return Response("500", $"nssm.exe 未找到: {nPath}");
            }
            string installArgs = $"remove \"{serviceName}\" confirm";
            if (RunNssmCommand(nPath, installArgs).Length > 0) {
                return Response("500", "failed to uninstall window service");
            }
            return "";
        }

        public static string RegisterWindowService(string nmPath, string serviceName, string executablePath, string arguments = "", string startType = "SERVICE_AUTO_START") {
            if (!File.Exists(nmPath)) {
                return Response("500", $"nssm.exe 未找到: {nmPath}");
            }

            if (!File.Exists(executablePath)) {
                return Response("500", $"可执行文件未找到: {executablePath}");
            }

            string installArgs = $"install \"{serviceName}\" \"{executablePath}\"";
            if (!string.IsNullOrWhiteSpace(arguments)) {
                installArgs += $" {arguments}";
            }

            if (RunNssmCommand(nmPath, installArgs).Length > 0) {
                return Response("500", "failed to install window service");
            }
            if (RunNssmCommand(nmPath, $"set \"{serviceName}\" DisplayName \"{serviceName}\"").Length > 0) {
                return Response("500", "failed to update service DisplayName");
            }
            if (RunNssmCommand(nmPath, $"set \"{serviceName}\" Description \"{serviceName}\"").Length > 0) {
                return Response("500", "failed to update service Description");
            }
            string logPath = Path.GetDirectoryName(executablePath) + "\\" + Path.GetFileNameWithoutExtension(executablePath) + ".log";
            if (!File.Exists(logPath)) {
                File.Create(logPath);
            }
            RunNssmCommand(nmPath, $"set \"{serviceName}\" AppStdin \"{logPath}\"");
            RunNssmCommand(nmPath, $"set \"{serviceName}\" AppStdout \"{logPath}\"");
            RunNssmCommand(nmPath, $"set \"{serviceName}\" AppStderr \"{logPath}\"");
            if (!string.IsNullOrWhiteSpace(startType)) {
                RunNssmCommand(nmPath, $"set \"{serviceName}\" Start {startType}");
            }
            RunNssmCommand(nmPath, $"set \"{serviceName}\" AppRestartDelay 5000");
            return "";
        }

        private static string RunNssmCommand(string nmPath, string arguments) {
            var startInfo = new ProcessStartInfo {
                FileName = nmPath,
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
                    if (process == null) {
                        return Response("500", "process == null");
                    }
                    process.WaitForExit();
                    if (!needAdmin) {
                        string output = process.StandardOutput.ReadToEnd();
                        string error = process.StandardError.ReadToEnd();
                        if (!string.IsNullOrEmpty(output)) {
                            Console.WriteLine(output);
                        }
                        if (!string.IsNullOrEmpty(error)) {
                            return Response("500", "错误: " + error);
                        }
                    }
                    if (process.ExitCode > 0) {
                        return Response("500", $"nssm 命令执行失败，退出代码: {process.ExitCode}");
                    }
                }
            } catch (Exception ex) {
                return Response("500", $"执行 nssm 命令失败: {ex.Message}");
            }
            return "";
        }

        private static bool IsAdministrator() {
            var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }

        public static string RunCommand(string command) {
            Process process = new Process();
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

        public static void PrintNetInfo() {
            string hostName = Dns.GetHostName();
            IPAddress[] addresses = Dns.GetHostAddresses(hostName);
            var data = addresses.Where(ip => ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip));
            string ipAddress = "";
            string subnetMask = "";
            foreach (var item in data) {
                if (ipAddress.Length < item.ToString().Length) {
                    ipAddress = item.ToString();
                    subnetMask = GetSubnetMaskForIp(item).ToString();
                }
            }
            Console.WriteLine($"Ip Address: \t{ipAddress}");
            Console.WriteLine($"Net Mask: \t{subnetMask}");

            foreach (var i in GetAllDnsServers()) {
                Console.WriteLine($"Dns: \t\t{i.ToString()}");
            }

            var proxyInfo = SystemProxyInfo.GetFromRegistry();
            Console.WriteLine($"Enable Proxy: \t{proxyInfo.Enabled}");
            Console.WriteLine($"Proxy Domain: \t{proxyInfo.Server}");
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

        public static string GetRuntimeDefaultProxy() {
            IWebProxy defaultProxy = WebRequest.DefaultWebProxy;
            if (defaultProxy != null) {
                Uri testUri = new Uri("http://www.baidu.com");
                Uri proxyUri = defaultProxy.GetProxy(testUri);
                return proxyUri.ToString();
            }
            return "";
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
