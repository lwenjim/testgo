using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.ServiceProcess;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    public class InstallService {
        static DateTime startDate = DateTime.Now;
        const string BinPath = "D:\\bin\\bin";
        const string DomainPath = "http://localhost";
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
                ServiceController specificService = new ServiceController(fileMapService[urlName]);
                bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(fileMapService[urlName], StringComparison.OrdinalIgnoreCase));
                if (serviceExists && (specificService.Status == ServiceControllerStatus.Running || specificService.Status == ServiceControllerStatus.Paused)) {
                    specificService.Stop();
                    specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }

                PathInfo info = GetBinPathFilenameAndLogname(urlName);
                string url = $"{DomainPath}/{info.filename}.exe";
                switch (Path.GetExtension(urlName)) {
                    case ".exe":
                        if (!fileMapService.ContainsKey(urlName)) {
                            return Response("500", "error params");
                        }
                        await DownloadFileWithHttpWebRequest(url, info.binPath);
                        break;
                    case ".zip":
                        url = $"{DomainPath}/{urlName}";
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

                if (!serviceExists) {
                    string nssmPath = "C:\\ProgramData\\chocolatey\\bin\\nssm.exe";
                    string fullName = $"{BinPath}\\{Path.GetFileName(urlName)}";
                    string serviceName = fileMapService[urlName];
                    string serviceDisplayName = serviceName;
                    string description = serviceName;
                    if (!NssmServiceInstaller.InstallService(nssmPath, serviceName, serviceDisplayName, description, fullName)) {
                        return Response("500", "failed to install");
                    }
                }
                if (specificService.Status == ServiceControllerStatus.Stopped) {
                    specificService.Start();
                    specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
                }
                return Response();
            } catch (Exception ex) {
                return Response("500", $"操作失败: {ex.Message}");
            }
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
                {"interval", (DateTime.Now.Subtract(startDate).TotalSeconds).ToString() },
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
    }
}
