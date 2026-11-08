using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Scriban;
using Serilog;

namespace ManageAnonTokyo {
    /// <summary>
    /// 请求级上下文：记录当前请求的起始时间戳，用于在响应中输出本次耗时。
    /// 使用 AsyncLocal 保证并发请求互不干扰。
    /// </summary>
    public static class RequestContext {
        private static readonly AsyncLocal<long> StartTimestamp = new();

        public static void Begin() {
            StartTimestamp.Value = Stopwatch.GetTimestamp();
        }

        public static long ElapsedMilliseconds {
            get {
                long start = StartTimestamp.Value;
                if (start == 0) {
                    return 0;
                }
                return (long)((Stopwatch.GetTimestamp() - start) * 1000.0 / Stopwatch.Frequency);
            }
        }
    }

    /// <summary>
    /// 统一的 API 响应格式：{ code, message, data?, interval }。
    /// </summary>
    public static class ApiResult {
        public const string SuccessCode = "200";
        public const string ErrorCode = "500";
        public const string SuccessMessage = "Service update successfully.";

        public static string Ok(string? data = null, string message = SuccessMessage) {
            return Serialize(SuccessCode, message, data);
        }

        public static string Fail(string message) {
            return Serialize(ErrorCode, message, null);
        }

        private static string Serialize(string code, string message, string? data) {
            var payload = new Dictionary<string, string> {
                ["code"] = code,
                ["message"] = message
            };
            if (data != null) {
                payload["data"] = data;
            }
            payload["interval"] = $"{RequestContext.ElapsedMilliseconds}ms";
            return JsonConvert.SerializeObject(payload) + "\n";
        }
    }

    public static class ApiServer {
        private const int MaxConcurrentRequests = 32;
        private static readonly SemaphoreSlim RequestSlots = new(MaxConcurrentRequests, MaxConcurrentRequests);

        public static async Task StartService(CancellationToken cancellationToken = default) {
            using HttpListener listener = new HttpListener();
            listener.Prefixes.Add(AppConfig.DomainExpose);
            listener.Start();
            Log.Information("Listen: {Domain}", AppConfig.DomainExpose);

            using var registration = cancellationToken.Register(() => {
                try {
                    listener.Stop();
                } catch (ObjectDisposedException) {
                }
            });

            try {
                while (!cancellationToken.IsCancellationRequested) {
                    HttpListenerContext context;
                    try {
                        context = await listener.GetContextAsync();
                    } catch (HttpListenerException) when (cancellationToken.IsCancellationRequested) {
                        break;
                    } catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) {
                        break;
                    }
                    _ = Task.Run(() => HandleRequestAsync(context), cancellationToken);
                }
            } catch (OperationCanceledException) {
                Log.Information("Service shutdown requested");
            } finally {
                listener.Stop();
                Log.Information("Listener stopped");
            }
        }

        private static async Task HandleRequestAsync(HttpListenerContext context) {
            await RequestSlots.WaitAsync();
            try {
                await ProcessRequest(context);
            } catch (Exception ex) {
                Log.Error(ex, "Request processing error");
                try {
                    SendResponse(context.Response, ApiResult.Fail($"Request processing error: {ex.Message}"));
                } catch (Exception responseEx) {
                    Log.Error(responseEx, "Failed to send error response");
                }
            } finally {
                RequestSlots.Release();
            }
        }

        private static async Task ProcessRequest(HttpListenerContext context) {
            var request = context.Request;
            RequestContext.Begin();
            Log.Information(
                "Received request: {Method} {Path} from {RemoteEP}",
                request.HttpMethod,
                request.Url!.AbsolutePath,
                request.RemoteEndPoint);

            if (await TryHandleApiRequest(context)) {
                return;
            }

            ServeStaticContent(context);
        }

        private static async Task<bool> TryHandleApiRequest(HttpListenerContext context) {
            switch (context.Request.Url!.AbsolutePath) {
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
                SendResponse(context.Response, ApiResult.Fail("Invalid executable name"));
                return;
            }
            if (!Deployer.IsKnownPackage(exeName)) {
                SendResponse(context.Response, ApiResult.Fail($"Invalid executable: {exeName}"));
                return;
            }

            string version = request.QueryString.Get("version") ?? "";
            IPEndPoint remoteIP = request.RemoteEndPoint;
            Log.Debug("Remote IP: {RemoteIP}", remoteIP);

            if (!await PortWatcher.IsPortOpenAsync(remoteIP.Address.ToString(), 80)) {
                SendResponse(context.Response, ApiResult.Fail($"Port 80 not open on {remoteIP.Address}"));
                return;
            }

            string responseString = await Deployer.Install(exeName, version, $"http://{remoteIP.Address}");
            Log.Information("Install response: {Response}", responseString);
            SendResponse(context.Response, responseString);
            Log.Information(
                "Handled deploy request for {ExeName} version {Version} from {RemoteAddr}",
                exeName,
                version,
                remoteIP.Address);
        }

        private static void HandleLoginRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string[]? usernames = request.QueryString.GetValues("username");
            string[]? passwords = request.QueryString.GetValues("password");
            if (usernames == null || usernames.Length == 0 || passwords == null || passwords.Length == 0) {
                SendJson(response, 500, ApiResult.Fail("error params"));
                return;
            }

            string token = TokenStore.Issue();
            response.Headers.Add("token", token);
            SendJson(response, 200, ApiResult.Ok(token, "ok"));
        }

        private static void HandleInfoRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string[]? tokens = request.QueryString.GetValues("token");
            if (tokens == null || tokens.Length == 0 || tokens[0].Length == 0) {
                SendJson(response, 500, ApiResult.Fail("error params"));
                return;
            }
            if (!TokenStore.TryValidate(tokens[0], out string error)) {
                SendJson(response, 500, ApiResult.Fail(error));
                return;
            }
            SendJson(response, 200, ApiResult.Ok(message: "ok"));
        }

        private static void ServeStaticContent(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;

            string absolutePath = request.Url!.AbsolutePath;
            string filePath = ResolveFilePath(absolutePath);

            if (File.Exists(filePath)) {
                ServeFile(response, filePath);
                return;
            }

            string directoryPath = Directory.Exists(filePath) ? filePath : AppConfig.BinPath;
            string indexPath = Path.Combine(directoryPath, AppConfig.DefaultIndex);
            if (File.Exists(indexPath)) {
                ServeFile(response, indexPath, "text/html; charset=utf-8");
                return;
            }

            ServeDirectoryListing(response, absolutePath, directoryPath);
        }

        private static string ResolveFilePath(string absolutePath) {
            string filePath = $"{AppConfig.BinPath}\\{absolutePath}";

            if (filePath.IndexOf("/sirius/dev/master") > -1) {
                filePath = Path.GetExtension(filePath) == ".zip"
                    ? Path.Combine(AppConfig.SiriusDevRoot, Path.GetFileName(filePath))
                    : AppConfig.SiriusDevRoot;
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

        private static void ServeDirectoryListing(
            HttpListenerResponse response,
            string basePath,
            string directoryPath) {
            response.ContentType = "text/html; charset=utf-8";
            DirectoryInfo info = new DirectoryInfo(directoryPath);

            var items = new List<Dictionary<string, string>>();
            foreach (var item in info.GetFileSystemInfos().OrderByDescending(f => f.LastWriteTime)) {
                string sizeStr = item is FileInfo file ? file.Length.ToString("N0") : "-";
                string href = (basePath + "/" + item.Name).Replace("//", "/");
                items.Add(new Dictionary<string, string> {
                    ["name"] = item.Name,
                    ["href"] = href,
                    ["size"] = sizeStr,
                    ["modified"] = item.LastWriteTime.ToString()
                });
            }

            string html = RenderDirectoryListing(basePath, items);
            byte[] buffer = Encoding.UTF8.GetBytes(html);
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        private static string RenderDirectoryListing(string basePath, List<Dictionary<string, string>> items) {
            var assembly = Assembly.GetExecutingAssembly();
            string resourceName = assembly.GetManifestResourceNames()
                .First(n => n.EndsWith("directory-listing.scriban", StringComparison.OrdinalIgnoreCase));
            using var stream = assembly.GetManifestResourceStream(resourceName)!;
            using var reader = new StreamReader(stream);
            string templateText = reader.ReadToEnd();

            var template = Template.Parse(templateText);
            return template.Render(new { base_path = basePath, items });
        }

        private static bool IsBinaryFile(string filePath, int sampleSize = 4096, double nonTextThreshold = 0.3) {
            using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            int size = (int)Math.Min(fs.Length, sampleSize);
            if (size == 0) {
                return false;
            }
            byte[] buffer = new byte[size];
            fs.Read(buffer, 0, size);
            int nonTextCount = 0;
            foreach (byte b in buffer) {
                if (b == 0x00) {
                    return true;
                }
                if (b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) {
                    nonTextCount++;
                }
            }
            return (double)nonTextCount / size > nonTextThreshold;
        }

        private static void SendResponse(HttpListenerResponse response, string responseString) {
            WriteBody(response, 200, responseString);
        }

        private static void SendJson(HttpListenerResponse response, int statusCode, string responseString) {
            WriteBody(response, statusCode, responseString);
        }

        private static void WriteBody(HttpListenerResponse response, int statusCode, string? responseString) {
            if (string.IsNullOrEmpty(responseString)) {
                response.OutputStream.Close();
                return;
            }
            response.StatusCode = statusCode;
            byte[] buffer = Encoding.UTF8.GetBytes(responseString);
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }
    }
}
