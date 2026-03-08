using System;
using System.Net;
using System.Text;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    // http://localhost:8082/?execName=anontokyo_server.exe
    internal class Program {
        static async Task Main(string[] args) {
            await StartService();
        }

        static async Task StartService() {
            string prefix = "http://localhost:8082/";
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(prefix);
            listener.Start();
            Console.WriteLine($"lissten: {prefix} port");
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
            string responseString = await InstallService.Install(exeName);
            Response(context.Response, responseString);
        }

        static void Response(HttpListenerResponse response, string responseString) {
            byte[] buffer = Encoding.UTF8.GetBytes(responseString);
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }
    }
}
