using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.ServiceProcess;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace ManageAnonTokyo {
    internal class Program {
        static DateTime startDate = DateTime.Now;
        static async Task Main(string[] args) {
            try {
                if (args.Length <= 0) {
                    Response("500", "error params");
                    return;
                }
                string urlName = args[0];
                Dictionary<string, string> config = new Dictionary<string, string>();
                config.Add("anontokyo_server.exe", "AnonTokyoServer");
                config.Add("AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer");
                config.Add("AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer");
                if (Path.GetExtension(urlName) == ".exe" && !config.ContainsKey(urlName)) {
                    Response("500", "error params");
                    return;
                }
                ServiceController specificService = new ServiceController(config[urlName]);
                bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals(config[urlName], StringComparison.OrdinalIgnoreCase));
                if (!serviceExists) {
                    Response("500", " not exists");
                    return;
                }
                if (specificService.Status == ServiceControllerStatus.Running) {
                    specificService.Stop();
                    specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }

                string[] info = GetBinPathFilenameAndLogname(urlName);
                string url = $"http://10.27.84.42/{info[1]}.exe";
                switch (Path.GetExtension(urlName)) {
                    case ".exe":
                        if (!config.ContainsKey(urlName)) {
                            Response("500", "error params");
                            return;
                        }
                        await DownloadFileWithHttpWebRequest(url, info[0]);
                        break;
                    case ".zip":
                        url = $"http://10.27.84.42/{urlName}";
                        if (File.Exists(info[0])) {
                            File.Delete(info[0]);
                        }
                        await DownloadFileWithHttpWebRequest(url, info[0]);
                        string distName = "D:\\bin\\bin";
                        if (Directory.Exists(distName + "\\mastercbor")) {
                            Directory.Delete(distName + "\\mastercbor", true);
                        }
                        ZipFile.ExtractToDirectory(info[0], distName);
                        break;
                    default:
                        Response("500", "error params");
                        return;
                }
                if (specificService.Status == ServiceControllerStatus.Stopped) {
                    specificService.Start();
                    specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
                }
                Response();
            } catch (Exception ex) {
                Response("500", $"操作失败: {ex.Message}");
            }
        }

        public static string[] GetBinPathFilenameAndLogname(string urlName) {
            string binPath = $"D:\\bin\\bin\\{urlName}";
            if (File.Exists(binPath)) {
                File.Delete(binPath);
            }
            string filename = Path.GetFileNameWithoutExtension(binPath);
            string logPath = string.Format("D:\\bin\\bin\\{0}.log", filename);
            if (!File.Exists(logPath)) {
                File.Create(logPath);
            }
            return new string[] { binPath, filename, logPath }
            ;
        }

        public static void Response(string code = "200", string message = "Service update successfully.") {
            Dictionary<string, string> scores = new Dictionary<string, string>();
            scores.Add("code", code);
            scores.Add("message", message);
            scores.Add("interval", (DateTime.Now.Subtract(startDate).TotalSeconds).ToString());
            string json = JsonConvert.SerializeObject(scores);
            Console.WriteLine($"{json}");
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
    }
}
