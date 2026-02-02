using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.ServiceProcess;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace ManageAnonTokyo
{

    internal class Program
    {
        static async Task Main(string[] args)
        {
            MainAsync(args);
        }
        static async void MainAsync(string[] args)
        {
            try
            {
                ServiceController specificService = new ServiceController("AnonTokyoServer");
                Console.WriteLine($"IIS服务状态: {specificService.Status}");
                bool serviceExists = ServiceController.GetServices().Any(s => s.ServiceName.Equals("AnonTokyoServer", StringComparison.OrdinalIgnoreCase));
                if (!serviceExists)
                {
                    Console.WriteLine(" not exists");
                    return;
                }
                if (specificService.Status == ServiceControllerStatus.Running)
                {
                    specificService.Stop();
                    specificService.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
                }
                string binPath = "D:\\bin\\bin\\anontokyo_server.exe";
                if (File.Exists(binPath))
                {
                    File.Delete(binPath);
                }
                string filename = Path.GetFileNameWithoutExtension(binPath);
                string logPath = string.Format("D:\\bin\\bin\\{0}.log", filename);
                if (!File.Exists(logPath))
                {
                    File.Create(logPath);
                }
                string url = $"http://10.27.84.42/{filename}.exe";
                await DownloadFileWithHttpWebRequest(url, binPath);
                if (specificService.Status == ServiceControllerStatus.Stopped)
                {
                    specificService.Start();
                    specificService.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"操作失败: {ex.Message}");
            }
        }

        public async static Task DownloadFileWithHttpWebRequest(string url, string filePath)
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "Mozilla/5.0";
            request.Timeout = 60000; // 30秒超时

            HttpWebResponse response = (HttpWebResponse)await request.GetResponseAsync();

            if (response.StatusCode == HttpStatusCode.OK)
            {
                Stream responseStream = response.GetResponseStream();
                FileStream fileStream = File.Create(filePath);

                byte[] buffer = new byte[4096];
                int bytesRead;
                long totalBytesRead = 0;

                while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, bytesRead);
                    totalBytesRead += bytesRead;

                    Console.WriteLine($"已下载: {totalBytesRead} bytes");
                }
            }
            else
            {
                throw new Exception($"HTTP错误: {response.StatusCode}");
            }
        }
    }
}
